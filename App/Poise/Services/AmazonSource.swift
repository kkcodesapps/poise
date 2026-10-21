import Foundation
import WebKit
import OSLog
import PoiseKit

private let log = Logger(subsystem: "com.koliokolev.poise", category: "amazon")

/// Reads the user's Amazon payments page, as them, on their phone.
///
/// Amazon gives a bank the amount and nothing else, so an Amazon charge in Poise is a number with no story. The one
/// page that ties a charge to an order is Amazon's own **Your Payments → Transactions**, and the only way to read it
/// is to be signed in. So the user signs in here, in a web view, on Amazon's own page — the session stays in this
/// app on this device, no password is ever seen or stored, and the only thing that leaves is an order number.
///
/// This reads one page and parses it. It never posts, buys, or follows a link the user didn't ask for.
@MainActor
final class AmazonSource: NSObject {
    static let shared = AmazonSource()

    enum Failure: Error { case signedOut, timedOut }

    /// Amazon's payments page only exists on the desktop site — a phone is redirected to a plain order list — so the
    /// read asks for the desktop one. Signing in stays on the phone site, where the form is a comfortable size.
    private static let desktopAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Safari/605.1.15"
    /// Amazon signs people out every few weeks; two minutes is plenty for a page that's already authenticated.
    private static let timeout: Duration = .seconds(30)

    /// Two web views over one cookie store, which is what the connection actually is.
    ///
    /// The visible one is only ever driven by the user, so nothing Poise does can navigate away from a half-typed
    /// password. The reader is off screen, wears the desktop agent, and is the only one this class loads pages into.
    private static func make(desktop: Bool) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()                       // persists to disk, sandboxed to Poise; shared by both
        config.defaultWebpagePreferences.allowsContentJavaScript = true
        let web = WKWebView(frame: CGRect(x: 0, y: 0, width: desktop ? 1180 : 393, height: 900), configuration: config)
        if desktop { web.customUserAgent = desktopAgent }
        return web
    }

    /// The one the user signs in on. Poise never loads a page into it except to start the flow.
    private(set) lazy var webView: WKWebView = Self.make(desktop: false)

    private lazy var reader: WKWebView = {
        let web = Self.make(desktop: true)
        web.navigationDelegate = self                              // only the reader is ever waited on
        return web
    }()

    private var waiting: CheckedContinuation<Void, Error>?

    // MARK: connection state

    private enum Key {
        static let connected = "amazonConnected", checkedAt = "amazonCheckedAt", lapsed = "amazonLapsed"
        static let ordersRead = "amazonOrdersRead", pagesRead = "amazonPagesRead", reachedBack = "amazonReachedBack"
    }

    /// What the last read actually saw. Kept because "it found nothing" and "it found plenty and matched nothing" are
    /// different faults, and the screen should be able to say which.
    private(set) var ordersRead: Int {
        get { UserDefaults.standard.integer(forKey: Key.ordersRead) }
        set { UserDefaults.standard.set(newValue, forKey: Key.ordersRead) }
    }

    private(set) var pagesRead: Int {
        get { UserDefaults.standard.integer(forKey: Key.pagesRead) }
        set { UserDefaults.standard.set(newValue, forKey: Key.pagesRead) }
    }

    /// The oldest order the last read got to. If this stops short of the oldest charge, the read ran out of road.
    private(set) var reachedBack: Date? {
        get { UserDefaults.standard.object(forKey: Key.reachedBack) as? Date }
        set { UserDefaults.standard.set(newValue, forKey: Key.reachedBack) }
    }

    /// The user connected at some point. Whether the session still works is `lapsed`.
    var isConnected: Bool {
        get { UserDefaults.standard.bool(forKey: Key.connected) }
        set { UserDefaults.standard.set(newValue, forKey: Key.connected) }
    }

    /// Amazon has signed them out. Not a failure — it happens every few weeks — so the app says so and carries on.
    var hasLapsed: Bool {
        get { UserDefaults.standard.bool(forKey: Key.lapsed) }
        set { UserDefaults.standard.set(newValue, forKey: Key.lapsed) }
    }

    var lastChecked: Date? {
        get { UserDefaults.standard.object(forKey: Key.checkedAt) as? Date }
        set { UserDefaults.standard.set(newValue, forKey: Key.checkedAt) }
    }

    /// Where the sign-in sheet starts. Amazon bounces to its own sign-in and lands back here afterwards, so the page
    /// we want is also the page that tells us we're in.
    var startURL: URL { AmazonOrders.transactionsPage }

    /// Puts the payments page in front of the user. Amazon redirects to its own sign-in when the session is gone, and
    /// back here once they're through it — so this is both the way in and the test of whether we're in.
    func start() {
        webView.load(URLRequest(url: startURL, cachePolicy: .reloadIgnoringLocalCacheData))
    }

    /// True while Amazon is still asking who they are.
    ///
    /// Its sign-in is several pages — email, then password, sometimes a one-time code — and between them the web view
    /// is briefly blank with no URL worth reading. A blank page is *not* being through, so it counts as still signing
    /// in; otherwise the gap between two of Amazon's own pages looks exactly like success.
    func isAtSignIn() async -> Bool {
        let url = webView.url?.absoluteString ?? ""
        if url.isEmpty || url.contains("/ap/") || url.contains("signin") || url.contains("validateCaptcha") { return true }
        let js = """
        (function () {
          if (!document.body || !document.body.innerText.trim()) { return true; }
          return !!document.querySelector('input[type=password], input[name=email], input[name=password], [id^=ap_email], [id^=ap_password], #auth-captcha-guess, input[name=otpCode], input[name=code], form[name=signIn]');
        })()
        """
        return ((try? await webView.evaluateJavaScript(js)) as? Bool) ?? true
    }

    // MARK: reading

    /// Loads the payments page and pages back through it.
    ///
    /// A page is about fifteen orders and a fortnight, so how far to walk depends on what's still missing rather than
    /// on a fixed count: it stops once it's read past `earliest`, or Amazon runs out of pages, or the cap is reached.
    func read(back earliest: Date?, maxPages: Int = 3, onPage: (@MainActor (Int, Date?) -> Void)? = nil) async throws -> [AmazonOrder] {
        try await load(AmazonOrders.transactionsPage)
        guard await signedIn() else { hasLapsed = true; throw Failure.signedOut }

        var orders: [AmazonOrder] = []
        var seen = Set<String>()
        var previous = ""
        var pages = 0
        var bounced = false
        for page in 0 ..< max(1, maxPages) {
            // Wait for the page to stop growing, not merely to differ. Amazon fills the list in as it renders, and
            // reading at the first sign of change caught half a page — which is why the same six pages came back as
            // 48 orders one run and 62 the next.
            // A page that doesn't settle gets one more chance: Amazon throttles a second run of page loads, and one slow
            // page was ending the whole walk.
            var settled = await settledText(differentFrom: previous)
            if settled == nil, page > 0 {
                try? await Task.sleep(for: .seconds(2))
                settled = await settledText(differentFrom: previous)
            }
            guard let text = settled else { break }
            // Amazon's payments page demands a sign-in from within the last hour, so a long-running or later check can
            // be bounced to re-authenticate half way down. That page isn't an empty page of orders — it's the end of
            // the read, and the user needs telling rather than a quietly shorter number.
            guard isPaymentsPage(text) else { bounced = true; break }
            previous = text
            pages = page + 1
            // Keyed on the whole listing: the same order number appears again when it's refunded, and both lines are real.
            let batch = AmazonOrders.parse(text)
            for order in batch {
                let listing = "\(order.id)|\(order.amount)|\(order.date.timeIntervalSince1970)"
                guard !seen.contains(listing) else { continue }
                seen.insert(listing)
                orders.append(order)
            }
            onPage?(pages, orders.map(\.date).min())
            // Past the oldest charge that still wants an order: everything older is already answered.
            if let earliest, let oldest = batch.map(\.date).min(), oldest < earliest { break }
            guard page + 1 < maxPages else { break }
            try? await Task.sleep(for: .milliseconds(600))          // a beat between pages; Amazon throttles a gallop
            guard await clickNextPage() else { break }
        }
        guard !bounced || !orders.isEmpty else { hasLapsed = true; throw Failure.signedOut }
        hasLapsed = bounced                                     // read what we could, but say the session is done
        lastChecked = .now
        // What's reported is the deepest read, not the latest. Order numbers already written stay written, so a later
        // run that sees less has lost nothing — and shouldn't look like it has.
        if orders.count >= ordersRead {
            ordersRead = orders.count
            pagesRead = pages
            reachedBack = orders.map(\.date).min()
        }
        log.info("read \(orders.count, privacy: .public) Amazon orders across \(pages, privacy: .public) pages")
        return orders
    }

    /// The page's text once it has settled: changed from the last page, not empty, and identical across two reads in a
    /// row so a list still being drawn isn't mistaken for a short one.
    private func settledText(differentFrom old: String, within seconds: Int = 30) async -> String? {
        var last = ""
        for _ in 0 ..< (seconds * 2) {
            let now = await innerText()
            if !now.isEmpty, now != old, now == last { return now }
            last = now
            try? await Task.sleep(for: .milliseconds(500))
        }
        return last.isEmpty || last == old ? nil : last
    }

    /// Opens one order's own page and reads what was in it. A page load per order, so callers ask for a few at a time
    /// rather than the lot — Amazon throttles a gallop and there is no bulk view of this.
    func readItems(for orderID: String) async throws -> AmazonOrderDetail? {
        try await load(AmazonOrders.url(for: orderID))
        guard let text = await settledText(differentFrom: ""), isOrderPage(text) else {
            if await isAtSignIn() { hasLapsed = true; throw Failure.signedOut }
            return nil
        }
        let detail = AmazonOrderDetails.parse(text, orderID: orderID)
        return detail.items.isEmpty ? nil : detail
    }

    private func isOrderPage(_ text: String) -> Bool {
        text.contains("Order Details") || text.contains("Order Summary")
    }

    /// The payments page itself, rather than a sign-in Amazon redirected us to.
    private func isPaymentsPage(_ text: String) -> Bool {
        text.contains("Transactions") && !text.contains("Enter mobile number or email") && !text.contains("Sign in to continue")
    }

    /// True once the payments page itself is on screen — the heading is the proof, not the URL, because Amazon will
    /// happily redirect a signed-out request somewhere that looks fine.
    func signedIn() async -> Bool {
        guard await !isAtSignIn() else { return false }
        let text = await innerText()
        return text.contains("Transactions") && !text.contains("Enter mobile number or email")
    }

    /// Forgets the session: Amazon's cookies and storage for this app, and the local flags. The order numbers already
    /// written to charges are cleared by the caller, so disconnecting really does leave nothing behind.
    func disconnect() async {
        let store = reader.configuration.websiteDataStore
        let types = WKWebsiteDataStore.allWebsiteDataTypes()
        let records = await store.dataRecords(ofTypes: types)
        let amazon = records.filter { $0.displayName.contains("amazon") }
        await store.removeData(ofTypes: types, for: amazon)
        isConnected = false
        hasLapsed = false
        lastChecked = nil
        ordersRead = 0
        pagesRead = 0
        reachedBack = nil
        for web in [webView, reader] { web.load(URLRequest(url: URL(string: "about:blank")!)) }
    }

    // MARK: the web view, waited on

    private func load(_ url: URL) async throws {
        finish(nil)                                                 // never leave an older wait hanging
        let deadline = Task { [weak self] in
            try await Task.sleep(for: Self.timeout)
            self?.finish(Failure.timedOut)
        }
        defer { deadline.cancel() }
        try await withCheckedThrowingContinuation { (c: CheckedContinuation<Void, Error>) in
            MainActor.assumeIsolated {
                self.waiting = c
                self.reader.load(URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData))
            }
        }
    }

    private func innerText() async -> String {
        let js = "document.body ? document.body.innerText : ''"
        return (try? await reader.evaluateJavaScript(js)) as? String ?? ""
    }

    /// Amazon's paging is a form control on the page, not a URL we can construct, so it has to be pressed — and the
    /// thing that says "Next Page" is a label span beside the submit input, not the input itself. Clicking the label
    /// does nothing at all, which is how the first version silently read one page and stopped.
    private func clickNextPage() async -> Bool {
        let js = """
        (function () {
          var label = Array.prototype.slice.call(document.querySelectorAll('span.a-button-text, span, input, a, button'))
            .find(function (e) { return ((e.innerText || e.value || '').trim()) === 'Next Page' && !e.disabled; });
          if (!label) { return false; }
          var host = label.closest('.a-button') || label.closest('.a-button-inner') || label.parentElement;
          var input = (host && host.querySelector('input[type=submit], input.a-button-input'))
                   || (label.tagName === 'INPUT' ? label : null);
          var target = input || label.closest('a, button');
          if (!target) { return false; }
          target.click();
          return true;
        })()
        """
        return ((try? await reader.evaluateJavaScript(js)) as? Bool) ?? false
    }

    private func finish(_ error: Error?) {
        guard let c = waiting else { return }
        waiting = nil
        if let error { c.resume(throwing: error) } else { c.resume() }
    }
}

extension AmazonSource: WKNavigationDelegate {
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { finish(nil) }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { finish(error) }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        // A redirect mid-flight cancels the previous navigation; that isn't a failure worth surfacing.
        if (error as NSError).code == NSURLErrorCancelled { return }
        finish(error)
    }
}
