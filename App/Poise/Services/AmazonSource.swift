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
    private var textOnly = false

    // MARK: connection state

    private enum Key {
        static let connected = "amazonConnected", checkedAt = "amazonCheckedAt", lapsed = "amazonLapsed"
        static let ordersRead = "amazonOrdersRead", pagesRead = "amazonPagesRead", reachedBack = "amazonReachedBack"
        static let unreadable = "amazonUnreadable"
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

    /// True when a page plainly had orders on it that Poise couldn't read — which means Amazon has changed the page,
    /// not that there was nothing to find. Without this the two look identical from the outside, and a redesign goes
    /// unnoticed until someone spots months of charges with no order against them.
    private(set) var pageUnreadable: Bool {
        get { UserDefaults.standard.bool(forKey: Key.unreadable) }
        set { UserDefaults.standard.set(newValue, forKey: Key.unreadable) }
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

    /// The reader wants words, not pictures. An Amazon order page carries a screenful of product photography and ad
    /// carousels, and seventy of them in a row is enough memory for iOS to kill the app — which arrives as a crash
    /// report. Blocking images, media and fonts in the reader only makes the sweep lighter and faster; the sign-in
    /// view is untouched and still looks like Amazon.
    private func useTextOnly() async {
        guard !textOnly, let store = WKContentRuleListStore.default() else { return }
        let rules = #"[{"trigger":{"url-filter":".*","resource-type":["image","media","font"]},"action":{"type":"block"}}]"#
        guard let list = try? await store.compileContentRuleList(forIdentifier: "poise-reader-text-only", encodedContentRuleList: rules) else { return }
        reader.configuration.userContentController.add(list)
        textOnly = true
    }

    /// Lets go of the page just read. Without this the last order's DOM sits in memory through the next load.
    private func releaseReader() async {
        try? await load(URL(string: "about:blank")!)
    }

    /// Puts the payments page in front of the user. Amazon redirects to its own sign-in when the session is gone, and
    /// back here once they're through it — so this is both the way in and the test of whether we're in.
    func start() {
        // If it was an order page Amazon stopped at, that is the page the user has to get past — the payments page
        // may well open without asking anything, which would close the sheet having fixed nothing.
        let url = challengeOrder.map(Self.orderURL) ?? startURL
        webView.load(URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData))
    }

    /// The order whose page Amazon wouldn't show without a sign-in or a check, until one is read again.
    private(set) var challengeOrder: String? {
        get { UserDefaults.standard.string(forKey: "amazonChallengeOrder") }
        set { UserDefaults.standard.set(newValue, forKey: "amazonChallengeOrder") }
    }

    static func orderURL(_ id: String) -> URL { URL(string: "https://www.amazon.com/your-orders/order-details?orderID=\(id)")! }

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
        await useTextOnly()
        try await load(AmazonOrders.transactionsPage)
        switch await landing() {
        case .signIn: hasLapsed = true; lastChecked = .now; throw Failure.signedOut
        case .unknown: throw Failure.timedOut                       // slow or odd page: try again later, don't cry wolf
        case .payments: break
        }

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
            // Order numbers on the page but nothing parsed out of it: the page has changed shape.
            if batch.isEmpty, text.contains("Order #") {
                pageUnreadable = true
                log.error("amazon page has orders but none could be read — layout changed")
            } else if !batch.isEmpty {
                pageUnreadable = false
            }
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
        // A walk that read nothing and ended on a page we don't recognise is a session that's gone.
        guard !bounced || !orders.isEmpty else { hasLapsed = true; lastChecked = .now; throw Failure.signedOut }
        // A walk that read orders and *then* hit something else has simply reached the end of the list — Amazon's
        // last page is not the payments page. Calling that a dropped session told the user to sign in again and, far
        // worse, made the phase that reads what was in each order give up before it started.
        hasLapsed = false
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
        await useTextOnly()
        // Straight to where Amazon now keeps order pages, rather than through the old address and its redirect.
        try await load(Self.orderURL(orderID))
        // Wait for something we recognise — the order itself, or a sign-in — not merely for the text to stop
        // changing, which a page in between can do for a second.
        var text = ""
        var readerAtSignIn = false
        for _ in 0 ..< 40 {
            text = await innerText()
            readerAtSignIn = await readerIsAtSignIn()
            if isOrderPage(text) && text.contains("Sold by") { break }
            if readerAtSignIn { break }
            try? await Task.sleep(for: .milliseconds(500))
        }
        var result: AmazonOrderDetail?
        if isOrderPage(text) {
            let detail = AmazonOrderDetails.parse(text, orderID: orderID)
            result = detail.items.isEmpty ? nil : detail
            if result == nil { lastItemFailure = "order page, nothing on it read" }
        } else if readerAtSignIn {
            let address = reader.url?.absoluteString ?? ""
            let captcha = address.contains("validateCaptcha") || text.contains("Enter the characters you see")
            // Which of Amazon's checks it was, and where — a step-up sign-in and a robot check need different things.
            lastItemFailure = (captcha ? "Amazon showed a robot check" : "Amazon wants a sign-in for order pages")
                + " (\(reader.url?.path ?? "?")\(address.contains("max_auth_age") ? ", fresh sign-in required" : ""))"
            challengeOrder = orderID
        } else {
            let path = reader.url?.path ?? "no address"
            lastItemFailure = "not an order page (\(path), \(text.count) chars)"
        }
        await releaseReader()                                       // before returning, so the next order starts clean
        // The reader is the one that opened the order, so it's the one that says whether Amazon wants a sign-in.
        if result == nil, readerAtSignIn { hasLapsed = true; throw Failure.signedOut }
        if result != nil { challengeOrder = nil }
        return result
    }

    /// Why the last order that couldn't be read couldn't be — so a failure says what it was instead of being a zero.
    private(set) var lastItemFailure: String?

    /// The same test as `isAtSignIn`, asked of the reader rather than the visible view.
    private func readerIsAtSignIn() async -> Bool {
        let url = reader.url?.absoluteString ?? ""
        if url.contains("/ap/") || url.contains("signin") || url.contains("validateCaptcha") { return true }
        let js = "!!document.querySelector('input[type=password], input[name=email], [id^=ap_email], [id^=ap_password], #auth-captcha-guess, input[name=otpCode], form[name=signIn]')"
        return ((try? await reader.evaluateJavaScript(js)) as? Bool) ?? false
    }

    private func isOrderPage(_ text: String) -> Bool {
        text.contains("Order Details") || text.contains("Order Summary")
    }

    /// The payments page itself, rather than a sign-in Amazon redirected us to.
    private func isPaymentsPage(_ text: String) -> Bool {
        text.contains("Transactions") && !text.contains("Enter mobile number or email") && !text.contains("Sign in to continue")
    }

    private enum Landing { case payments, signIn, unknown }

    /// Where the reader ended up after asking for the payments page, waited for rather than read at once.
    ///
    /// Asked of the reader, which is the view that just loaded the page. The visible view has loaded nothing on a cold
    /// launch, and `isAtSignIn` counts a view with no page as still signing in — so asking it called every check after
    /// a restart a dropped session. And only a sign-in form counts as signed out: a page still drawing, or one Amazon
    /// served slowly, is a check to try again, not a reason to tell the user to sign in.
    private func landing() async -> Landing {
        for _ in 0 ..< 30 {
            if await readerIsAtSignIn() { return .signIn }
            let text = await innerText()
            if isPaymentsPage(text) { return .payments }
            try? await Task.sleep(for: .milliseconds(500))
        }
        return .unknown
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
