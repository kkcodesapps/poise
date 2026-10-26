import Foundation
import AuthenticationServices
import Observation
import OSLog
import Supabase
import UserNotifications
import WidgetKit
import PoiseKit

private let log = Logger(subsystem: "com.koliokolev.poise", category: "app")

/// The only UI state. Views read from here; services write here. Everything derived is recomputed in one place.
@MainActor @Observable
final class AppModel {
    enum Tab: String, CaseIterable, Identifiable {
        // The tab is just "Next"; the screen's own title says how far ahead it's looking.
        case home = "Home", leaks = "Leaks", pace = "Pace", next14 = "Next", whereTab = "Where"
        var id: String { rawValue }
        var symbol: String {
            switch self {
            case .home: "house"
            case .leaks: "drop"
            case .pace: "chart.line.uptrend.xyaxis"
            case .next14: "calendar"
            case .whereTab: "chart.bar.doc.horizontal"
            }
        }
    }

    var tab: Tab = .home
    var accounts: [Account] = []
    /// Taken out of the math by the user; listed under Hidden accounts, never handed to the engine.
    var hiddenAccounts: [Account] = []
    var transactions: [PoiseKit.Transaction] = []
    /// The feed's copy: one row per movement. Both halves of a transfer or card payment are real, and the engines need
    /// both, but a feed showing each twice reads as paying twice.
    var feed: [PoiseKit.Transaction] = []
    var streams: [RecurringStream] = []
    var verdict: Verdict?
    var pace: Pace?
    var cashflow: [CashflowDay] = []
    var insights: [Insight] = []
    var reviewCards: [ReviewCard] = []
    var fees: Anomalies.Fees = .init(total: 0, items: [])
    var settings = Repository.Settings()
    var customCategories: [PoiseKit.Category] = []
    var categories: CategorySet = .builtIn
    var watches: [Watch] = []
    var wherePeriod: Period = .month { didSet { whereWindow = Periods.window(wherePeriod, containing: whereAnchor) } }
    /// How far ahead the Next screen looks. A fortnight answers "can I reach payday"; a month catches rent, a
    /// quarterly bill or an annual renewal sitting just past that edge. Per device, and remembered.
    var horizonDays: Int = UserDefaults.standard.object(forKey: "horizonDays") as? Int ?? 14 {
        didSet {
            guard horizonDays != oldValue else { return }
            UserDefaults.standard.set(horizonDays, forKey: "horizonDays")
            recompute()
        }
    }
    var whereAnchor: Date = .now
    var whereWindow: DateInterval = Periods.window(.month, containing: .now)
    var showWatching = false
    #if DEBUG
    /// Debug only: an account page to open once Settings is up.
    var openAccount: String?
    #endif
    var profilePath: [String] = []
    /// The card whose page Home has open, if any.
    var openCard: String?
    /// The card whose Look & name sheet is up, from Home's press-and-hold or the card's page.
    var lookCard: String?
    var lastSync: Date?
    var institutions: [String] = []
    var relinkNeeded: [Repository.Item] = []
    /// Banks holding cards whose due dates Poise was never granted. Their payments are missing from Next until the
    /// user goes back through Link and allows it.
    var statementConsentNeeded: [Repository.Item] = []
    /// Apple Card / Apple Cash / Savings are read from Wallet on this phone; true once the server has that item.
    var walletLinked = false
    /// Wallet access was turned off in Settings after linking; the banner sends the user back there.
    var walletAccessLost = false
    /// Amazon, connected by signing in on this phone. The session lives in the web view; these mirror it for the views.
    var amazonConnected = false
    /// Amazon signed the user out — expected every few weeks, and said out loud rather than left to rot.
    var amazonLapsed = false
    var amazonCheckedAt: Date?
    var amazonReading = false
    /// How far along a read is, 0 to 1. Amazon never says how many pages it holds, so this is a curve that always
    /// moves and never claims to be finished — it snaps to full when the read actually ends.
    var amazonProgress: Double = 0
    /// The oldest order reached so far, which is the honest thing to show while it walks backwards.
    var amazonReadingBackTo: Date?
    /// What the last read saw, whether or not any of it matched a charge.
    /// What was in each order, by order number. Two charges from one order share a single entry.
    var orderItems: [String: AmazonOrderDetail] = [:]
    /// Orders currently being fetched, so a sheet can show that it's working and can't ask twice.
    var fetchingItems: Set<String> = []
    /// The long read, owned here rather than by the screen that started it — closing that screen must not stop it.
    private var amazonSweep: Task<Void, Never>?
    /// The second phase of a check: reading what was in each order. Zero when that phase isn't running.
    var amazonItemsTotal = 0
    var amazonItemsDone = 0
    /// What the last item phase managed, so a phase that quietly does nothing can be seen rather than guessed at.
    var amazonItemsRead = 0
    var amazonItemsWanted = 0
    /// Why the last one that failed did.
    var amazonItemsFailure: String?
    var amazonOrdersRead = 0
    var amazonPagesRead = 0
    /// The oldest order the last read reached. Short of the oldest charge means it ran out of road, not out of matches.
    var amazonReachedBack: Date?
    #if DEBUG
    enum AmazonScreen { case connect, signIn, reading, connection }
    var showAmazon: AmazonScreen?
    #endif
    /// How many Amazon charges carry an order number, for the screen that reports on a connection.
    var amazonMatched: Int { raw.reduce(0) { $0 + ($1.orderRef == nil ? 0 : 1) } }
    var amazonCharges: Int { raw.filter { $0.merchantKey.hasPrefix("amazon") && !$0.pending }.count }
    /// The first-run screens (Figma §01); nil once the user is through them or has linked something.
    enum OnboardingStep: Equatable { case welcome, link, reading, payday }
    var onboarding: OnboardingStep?
    var showLinkOptions = false
    private var lastForegroundRefresh: Date?
    var isLoading = false
    var isLinking = false
    var errorMessage: String?
    var selectedTransaction: PoiseKit.Transaction?
    var selectedStream: RecurringStream?
    var showSince = false
    var newCategoryOnLaunch = false
    #if DEBUG
    var showWidgetPreview = false
    #endif
    /// Pushes: iOS's answer, and whether we've asked in our own words yet.
    var pushStatus: UNAuthorizationStatus = .notDetermined
    private(set) var askedForPush = UserDefaults.standard.bool(forKey: "askedForPush")
    var showPushAsk: Bool { looksLinked && !askedForPush && pushStatus == .notDetermined && launch == .ready }
    struct MerchantRef: Identifiable, Sendable { let key: String; var id: String { key } }
    var selectedMerchant: MerchantRef?
    /// Prices: what you pay for the things you buy again (PriceTracker). They live on the Where tab's second mode.
    var priceItems: [PriceItem] = []
    enum WhereMode: String, CaseIterable { case spending = "Spending", prices = "Prices" }
    var whereMode: WhereMode = .spending
    /// The Where tab's navigation path — a category id pushes its page.
    var wherePath: [String] = []
    /// Which chip the Prices list opens on — "up" from the Leaks tile.
    var pricesFilter = "all"
    /// The day the screens are drawn against. Relative labels ("TODAY", "yesterday") read from this, not from `Date.now`,
    /// so an app left open across midnight doesn't keep calling yesterday today.
    private(set) var today = Calendar.current.startOfDay(for: .now)
    private var midnight: Task<Void, Never>?
    private var lateDelivery: Task<Void, Never>?

    /// Every stream the detector found, ended ones included; `streams` is the live subset the engines use.
    var allStreams: [RecurringStream] = []
    /// Subscriptions and bills that stopped: marked cancelled by the user, or quiet for two periods on their own.
    var endedStreams: [RecurringStream] = []
    struct PriceItemRef: Identifiable, Sendable { let id: String }
    var selectedPriceItem: PriceItemRef?
    /// What changed since the app was last in front. Nil when there's nothing to say.
    var since: Since?
    struct Since: Sendable {
        var lastLooked: Date
        var new: [PoiseKit.Transaction] = []
        var posted: [PoiseKit.Transaction] = []
        var payments: [PoiseKit.Transaction] = []
        var refunds: [PoiseKit.Transaction] = []
        var isEmpty: Bool { new.isEmpty && posted.isEmpty }
        /// "3 new charges · 1 posted · Apple Card paid $2,073"
        var summary: String {
            var parts: [String] = []
            let charges = new.filter { $0.kind != .ccPayment && $0.kind != .refund }
            if !charges.isEmpty { parts.append("\(charges.count) new charge\(charges.count == 1 ? "" : "s")") }
            if !posted.isEmpty { parts.append("\(posted.count) posted") }
            if !refunds.isEmpty { parts.append(refunds.count == 1 ? "\(refunds[0].displayMerchant) refund \(refunds[0].magnitude.money)" : "\(refunds.count) refunds") }
            if !payments.isEmpty { parts.append(payments.count == 1 ? "card paid \(payments[0].magnitude.money)" : "\(payments.count) cards paid") }
            return parts.joined(separator: " · ")
        }
    }
    /// The insight a sheet was opened from. The sheet's "why it's here" card shows only then.
    var insightContext: Insight?
    var showProfile = false
    var showReview = false
    var isLocked = false
    var isAnonymous = true
    /// The splash: shown from the first frame until the first load settles.
    enum LaunchPhase { case loading, failed, ready }
    var launch: LaunchPhase = .loading
    /// Remembered across launches so a returning user never sees the empty verdict while a load is still running.
    private(set) var rememberedLinked = UserDefaults.standard.bool(forKey: "hasLinkedBefore")
    var accountName: String?

    private let repository = Repository(client: Backend.client)
    private var linker: BankLinker?
    private let wallet = WalletSource(client: Backend.client)
    private var raw: [PoiseKit.Transaction] = []
    private var logos: [String: String] = [:]
    private(set) var acknowledged: Set<String> = Set(UserDefaults.standard.stringArray(forKey: "acknowledgedInsights") ?? [])

    var hasLinkedBank: Bool { !accounts.isEmpty || !hiddenAccounts.isEmpty }
    /// What the screens key their empty states off: linked now, or linked the last time we looked.
    var looksLinked: Bool { hasLinkedBank || rememberedLinked }
    var allAccounts: [Account] { accounts + hiddenAccounts }
    func account(id: String) -> Account? { allAccounts.first { $0.id == id } }
    struct AccountGroup: Identifiable { let institution: String; let accounts: [Account]; var id: String { institution } }
    /// Accounts by institution, institutions in the order their first account sorts (spending first).
    func grouped(_ list: [Account]) -> [AccountGroup] {
        var order: [String] = [], byName: [String: [Account]] = [:]
        for a in list.sorted(by: { ($0.role.order, $0.name) < ($1.role.order, $1.name) }) {
            let key = a.institution ?? "Accounts"
            if byName[key] == nil { order.append(key) }
            byName[key, default: []].append(a)
        }
        return order.map { AccountGroup(institution: $0, accounts: byName[$0] ?? []) }
    }
    var walletAvailable: Bool { WalletSource.isAvailable }
    var topInsight: Insight? { insights.first }
    var isReviewDay: Bool { Calendar.current.component(.weekday, from: .now) == 1 }
    /// Refund and merchant watches — the priority list. Price watches live under Prices, not Watching.
    var openWatches: [Watch] { watches.filter { $0.status.isOpen && $0.kind != .price } }
    var owedBack: Decimal { openWatches.filter { $0.kind == .refund }.reduce(0) { $0 + ($1.expectedAmount ?? 0) } }
    func watch(for transactionID: String) -> Watch? { watches.first { $0.transactionID == transactionID && $0.status.isOpen } }
    func isWatched(merchantKey: String) -> Bool { watches.contains { $0.kind == .merchant && $0.matcher == merchantKey && $0.status.isOpen } }

    /// Errors worth an alert. A cancelled request — the pull ended, the view went away, the app backgrounded — isn't one.
    private func report(_ error: Error) {
        if error is CancellationError || (error as? URLError)?.code == .cancelled { return }
        errorMessage = error.localizedDescription
    }

    /// Where: the current window's breakdown, recomputed on demand.
    var breakdown: Breakdown? {
        guard hasLinkedBank else { return nil }
        return CategoryBreakdown.compute(transactions: transactions.filter { !$0.excluded }, period: wherePeriod, window: whereWindow, now: .now, categories: categories)
    }
    var whereIsCurrent: Bool { whereWindow.contains(.now) }

    /// The cards, in the order Home lays them out: the one carrying the most first.
    var cards: [Account] { accounts.filter { $0.role == .credit }.sorted { ($0.owed, $0.name) > ($1.owed, $1.name) } }
    /// Everything that happened on one account — the raw rows, for the breakdown, and the feed's, for the list.
    func transactions(on accountID: String) -> [PoiseKit.Transaction] { transactions.filter { $0.accountID == accountID && !$0.excluded } }
    /// Where, for one card: the same breakdown over only its rows, in Where's own period and window.
    func breakdown(account accountID: String) -> Breakdown {
        CategoryBreakdown.compute(transactions: transactions(on: accountID), period: wherePeriod, window: whereWindow, now: .now, categories: categories)
    }
    /// What went on a card this calendar month, whatever Where is showing — the figure on its tile.
    func monthSpend(account accountID: String) -> Decimal {
        CategoryBreakdown.compute(transactions: transactions(on: accountID), period: .month, window: Periods.window(.month, containing: .now), now: .now, categories: categories).total
    }
    /// The whole of last calendar month on a card — what its tile measures this month against.
    func lastMonthSpend(account accountID: String) -> Decimal {
        let w = Periods.shift(Periods.window(.month, containing: .now), .month, by: -1)
        return CategoryBreakdown.compute(transactions: transactions(on: accountID), period: .month, window: w, now: .now, categories: categories).total
    }
    func stepWhere(_ n: Int) { let w = Periods.shift(whereWindow, wherePeriod, by: n); if w.start <= .now { whereWindow = w; whereAnchor = w.start } }

    /// Launch: sign in, first load, settle the splash (never under half a second, never over eight), then the extras.
    func start() async {
        launch = .loading
        let began = Date.now
        let watchdog = Task { try? await Task.sleep(for: .seconds(8)); if launch == .loading { launch = .failed } }
        defer { watchdog.cancel() }
        #if DEBUG
        // `-slow-launch` holds the first load 3 s (shows the reading state); `-fail-launch` lands on the can't-connect state.
        if ProcessInfo.processInfo.arguments.contains("-slow-launch") { try? await Task.sleep(for: .seconds(3)) }
        if ProcessInfo.processInfo.arguments.contains("-fail-launch") { launch = .failed; return }
        #endif
        do {
            try await Backend.ensureSession()
            await readSession()
            var loaded = false
            if let id = try? await Backend.client.auth.session.user.id.uuidString, let cached = SnapshotCache.load(for: id) {
                // Yesterday's numbers now, today's as soon as the network answers.
                apply(cached.snapshot, cached.settings)
                loaded = true
                Task { await reload() }
            } else {
                loaded = await reload()
            }
            if !loaded, !hasLinkedBank { errorMessage = nil; launch = .failed; return }   // nothing to show behind the splash
            let elapsed = Date.now.timeIntervalSince(began)
            if elapsed < 0.5 { try? await Task.sleep(for: .seconds(0.5 - elapsed)) }
            launch = .ready
            rollDay()
            if !looksLinked, !UserDefaults.standard.bool(forKey: "onboardingDone") { onboarding = isAnonymous ? .welcome : .link }
            await refreshPushStatus()
            if settings.faceID { isLocked = true; await unlock() }
            if walletLinked { WalletSource.setBackgroundDelivery(true); Task { if await syncWallet() { await reload() } } }
            let amazon = AmazonSource.shared
            amazonConnected = amazon.isConnected; amazonLapsed = amazon.hasLapsed; amazonCheckedAt = amazon.lastChecked
            amazonOrdersRead = amazon.ordersRead; amazonPagesRead = amazon.pagesRead; amazonReachedBack = amazon.reachedBack
            // A connected Amazon is checked on launch, at most every six hours — new charges arrive with their order.
            Task { await syncAmazonIfDue(notBefore: 6 * 3600, maxPages: 3, items: 8) }
            // An unfinished sweep resumes on its own: it only ever reads orders that still want reading.
            if amazonConnected, !amazonLapsed, raw.contains(where: { $0.orderRef.map(needsReading) ?? false }) {
                startAmazonSweep()
            }
            #if DEBUG
            // `-tab leaks|pace|next14` and `-review` open a screen on launch (screenshots, UI tests).
            let args = ProcessInfo.processInfo.arguments
            if let i = args.firstIndex(of: "-tab"), i + 1 < args.count {
                let want = args[i + 1].lowercased()
                tab = Tab.allCases.first { $0.rawValue.lowercased().replacingOccurrences(of: " ", with: "") == want || "\($0)".lowercased() == want } ?? .home
            }
            if args.contains("-review") { showReview = true }
            if args.contains("-watching") { showWatching = true }
            if args.contains("-amazon-progress") { amazonReading = true; amazonItemsTotal = 71; amazonItemsDone = 30 }
            // `-card <name>` opens a card's page from Home, so it can be looked at without tapping through; add `-look`
            // for its Look & name sheet instead.
            // Waits for the accounts to arrive: at launch they usually haven't yet.
            if let i = args.firstIndex(of: "-card"), i + 1 < args.count {
                let want = args[i + 1].lowercased()
                Task { @MainActor in
                    for _ in 0 ..< 40 {
                        if let a = accounts.first(where: { $0.role == .credit && $0.name.lowercased().contains(want) }) {
                            tab = .home
                            if args.contains("-look") { lookCard = a.id } else { openCard = a.id }
                            return
                        }
                        try? await Task.sleep(for: .milliseconds(500))
                    }
                }
            }
            if let i = args.firstIndex(of: "-horizon"), i + 1 < args.count, let d = Int(args[i + 1]) { horizonDays = d }
            // `-amazon [connect|signin|connection]` opens the Amazon screens (screenshots, checks).
            if let i = args.firstIndex(of: "-amazon") {
                let which = i + 1 < args.count ? args[i + 1] : "connect"
                showAmazon = which == "connection" ? .connection : which == "signin" ? .signIn : which == "reading" ? .reading : .connect
                if showAmazon == .reading {
                    amazonReading = true; amazonProgress = 0.88
                    amazonReadingBackTo = Calendar.current.date(byAdding: .day, value: -44, to: .now)
                    amazonOrdersRead = 71; amazonPagesRead = 6
                    amazonItemsTotal = 71; amazonItemsDone = 30
                }
            }
            // `-onboarding [welcome|link|reading|payday]` opens the first-run flow at a step, whatever the account looks like.
            if let i = args.firstIndex(of: "-onboarding") {
                let step = i + 1 < args.count ? args[i + 1] : "welcome"
                onboarding = ["welcome": .welcome, "link": .link, "reading": .reading, "payday": .payday][step] ?? .welcome
            }
            if args.contains("-profile") { showProfile = true }
            if args.contains("-categories") { showProfile = true; profilePath = ["categories"] }
            if args.contains("-new-category") { showProfile = true; profilePath = ["categories"]; newCategoryOnLaunch = true }
            if args.contains("-watching") { showProfile = true; profilePath = ["watching"] }
            // `-account` / `-hidden` open the first account's page / the hidden list; `-hide-first` hides the first account first.
            if args.contains("-hide-first"), let a = accounts.first { await setHidden(true, for: a); showProfile = true; profilePath = ["account:\(a.id)"] }
            else if args.contains("-account"), let a = allAccounts.first { showProfile = true; profilePath = ["account:\(a.id)"] }
            else if args.contains("-account-card"), let a = allAccounts.first(where: { $0.role == .credit }) { showProfile = true; profilePath = ["account:\(a.id)"] }
            if args.contains("-hidden") { showProfile = true; profilePath = ["hidden"] }
            // `-open-insight dup|fee|price` opens the first insight of that kind the way a Leaks row would; `-open-stream` the first subscription.
            if let i = args.firstIndex(of: "-open-insight"), i + 1 < args.count {
                let kind: Insight.Kind? = ["dup": .duplicate, "fee": .fee, "price": .priceUp][args[i + 1]]
                if let ins = insights.first(where: { $0.kind == kind }) { Task { try? await Task.sleep(for: .seconds(1)); open(ins) } }   // after the splash fade
            }
            if args.contains("-open-stream"), let s = streams.first(where: { $0.kind == .subscription }) { selectedStream = s }
            // `-open-stream-txn` opens the newest charge of the first subscription (the sheet's "It repeats" section).
            if args.contains("-open-stream-txn"), let s = streams.first(where: { $0.kind == .subscription }),
               let t = transactions.first(where: { $0.id == s.transactionIDs.last }) { Task { try? await Task.sleep(for: .seconds(1)); selectedTransaction = t } }
            // `-open-ended` opens the first cancelled/ended subscription (the muted sheet states).
            if args.contains("-open-ended"), let s = endedStreams.first { Task { try? await Task.sleep(for: .seconds(1)); selectedStream = s } }
            // `-open-merchant` opens the merchant page for the first spend charge; `-since` the since-you-last-looked sheet.
            if args.contains("-open-merchant"), let t = transactions.first(where: { $0.kind == .spend }) { Task { try? await Task.sleep(for: .seconds(1)); selectedMerchant = .init(key: t.merchantKey) } }
            if args.contains("-since") { Task { try? await Task.sleep(for: .seconds(1)); showSince = true } }
            // `-stale-day` pretends the app was left open overnight: the feed is drawn against yesterday, then rolls.
            if args.contains("-stale-day") {
                pretendYesterday()
                Task { try? await Task.sleep(for: .seconds(4)); rollDay() }
            }
            if args.contains("-widgets") { Task { try? await Task.sleep(for: .seconds(1)); showWidgetPreview = true } }
            // `-seed-prices` names the seeded Amazon orders so an item exists; `-prices` opens the list; `-open-item` the first item.
            if args.contains("-seed-prices") {
                try await Backend.client.functions.invoke("financekit-sync", options: FunctionInvokeOptions(headers: ["content-type": "application/json"], body: DebugSeed.prices))
                await reload()
                for t in raw where t.id.hasPrefix("seed-price-") || t.merchant == "Amazon" && t.magnitude < 40 { await rename(t, to: "Naked Whey Protein", always: false) }
            }
            if args.contains("-prices") { showPricesList() }
            // `-open-txn-item` opens the latest purchase of the first item (the sheet's price card + name suggestions).
            if args.contains("-open-txn-item"), let item = pricesMovedLately.first ?? priceItems.first, let t = transactions.first(where: { $0.id == item.purchases.last?.id }) { Task { try? await Task.sleep(for: .seconds(1)); selectedTransaction = t } }
            if args.contains("-open-item"), let item = pricesMovedLately.first ?? priceItems.first { Task { try? await Task.sleep(for: .seconds(1)); selectedPriceItem = .init(id: item.id) } }
            // `-open-plan` opens a plan's page — the one that carries the usage strip.
            if args.contains("-open-plan"), let item = priceItems.first(where: { $0.hasUsage }) ?? priceItems.first(where: { $0.source == .plan }) { Task { try? await Task.sleep(for: .seconds(1)); selectedPriceItem = .init(id: item.id) } }
            // `-push-provisional` registers for pushes without a prompt (quiet delivery), so the token → server → APNs chain can be checked.
            if args.contains("-push-provisional") {
                _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.provisional, .alert, .sound])
                await refreshPushStatus()
            }
            // `-open-txn` opens the first spend charge's sheet; `-rename-first X` / `-note-first X` / `-exclude-first` exercise "what was this".
            if let t = transactions.first(where: { $0.kind == .spend && !$0.pending }) {
                if args.contains("-open-txn") { Task { try? await Task.sleep(for: .seconds(1)); selectedTransaction = t } }
                if let i = args.firstIndex(of: "-rename-first"), i + 1 < args.count { await rename(t, to: args[i + 1], always: true) }
                if let i = args.firstIndex(of: "-note-first"), i + 1 < args.count { await setNote(t, note: args[i + 1]) }
                if args.contains("-exclude-first") { await setExcluded(t, true) }
            }
            // `-seed-more` lands one more Wallet-shaped row (a "new since you last looked").
            // `-dump-next14` writes the streams and the cash-flow days to Documents/next14.txt (simulator checks).
            if args.contains("-dump-next14") {
                var out = streams.map { s in "STREAM \(s.id) \(s.kind) \(s.cadence) \(s.amount) last \(s.lastSeen.formatted(date: .abbreviated, time: .omitted)) next \(s.nextExpected.formatted(date: .abbreviated, time: .omitted)) acct \(s.accountID ?? "-") rows \(s.transactionIDs.count)" }
                out += cashflow.map { d in "DAY \(d.date.formatted(date: .abbreviated, time: .omitted)) after \(d.balanceAfter) lines \(d.lines.map { "\($0.name) \($0.amount)\($0.viaCard.map { " via \($0)" } ?? "")" })" }
                let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("next14.txt")
                try? out.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
            }
            if args.contains("-seed-bills") {
                try await Backend.client.functions.invoke("financekit-sync", options: FunctionInvokeOptions(headers: ["content-type": "application/json"], body: DebugSeed.bills))
                await reload()
            }
            // `-open-ccpay` opens a card payment's sheet — the row a bank may sign either way.
            if args.contains("-open-ccpay"), let t = transactions.first(where: { $0.kind == .ccPayment && $0.amount > 0 }) { Task { try? await Task.sleep(for: .seconds(1)); selectedTransaction = t } }
            if args.contains("-seed-years") {
                try await Backend.client.functions.invoke("financekit-sync", options: FunctionInvokeOptions(headers: ["content-type": "application/json"], body: DebugSeed.years))
                await reload()
            }
            // `-open-category <id>` opens a category's page (groceries by default).
            if args.contains("-open-category") {
                let i = args.firstIndex(of: "-open-category")!
                let id = i + 1 < args.count && !args[i + 1].hasPrefix("-") ? args[i + 1] : "groceries"
                whereMode = .spending; tab = .whereTab; wherePath = [id]
            }
            if args.contains("-seed-store") {
                try await Backend.client.functions.invoke("financekit-sync", options: FunctionInvokeOptions(headers: ["content-type": "application/json"], body: DebugSeed.store))
                await reload()
            }
            // `-open-store` opens the merchant page of a shop with no price (the "A store, not a price" card).
            if args.contains("-open-store"), let t = transactions.first(where: { storeShape(merchantKey: $0.merchantKey) != nil }) { Task { try? await Task.sleep(for: .seconds(1)); selectedMerchant = .init(key: t.merchantKey) } }
            if args.contains("-seed-ccpay") {
                try await Backend.client.functions.invoke("financekit-sync", options: FunctionInvokeOptions(headers: ["content-type": "application/json"], body: DebugSeed.cardPayment))
                await reload()
            }
            if args.contains("-seed-leaks") {
                try await Backend.client.functions.invoke("financekit-sync", options: FunctionInvokeOptions(headers: ["content-type": "application/json"], body: DebugSeed.leaks))
                await reload()
            }
            // `-cancel-first` marks the first live subscription cancelled 60 days ago, so its later charges become the top leak.
            if args.contains("-cancel-first"), let s = streams.first(where: { $0.kind == .subscription }) { await cancel(s, on: Calendar.current.date(byAdding: .day, value: -60, to: .now)!) }
            if args.contains("-seed-payroll") {
                try await Backend.client.functions.invoke("financekit-sync", options: FunctionInvokeOptions(headers: ["content-type": "application/json"], body: DebugSeed.payroll))
                await reload()
            }
            if args.contains("-seed-more") {
                try await Backend.client.functions.invoke("financekit-sync", options: FunctionInvokeOptions(headers: ["content-type": "application/json"], body: DebugSeed.more))
                await reload()
            }
            // `-link` opens Plaid Link a moment after launch (with `-profile`, from inside the sheet).
            if args.contains("-link") { Task { try? await Task.sleep(for: .seconds(1.5)); await link() } }
            // `-seed` pushes a fixed set of Wallet-shaped accounts and rows through the real sync (see DebugSeed).
            if args.contains("-seed") {
                try await Backend.client.functions.invoke("financekit-sync", options: FunctionInvokeOptions(headers: ["content-type": "application/json"], body: DebugSeed.wallet))
                await reload()
            }
            // `-sandbox-link` on the launch arguments links Plaid's test bank without the Link UI (sandbox only).
            if !hasLinkedBank, ProcessInfo.processInfo.arguments.contains("-sandbox-link") {
                try await Backend.client.functions.invoke("sandbox-link")
                await reload()
            }
            #endif
        } catch {
            log.error("start failed: \(error.localizedDescription, privacy: .public)")
            if error is CancellationError { return }
            if launch == .loading { launch = .failed } else { report(error) }
        }
    }

    @discardableResult
    func reload(retry: Bool = true) async -> Bool {
        isLoading = true; defer { isLoading = false }
        do {
            async let snap = repository.load()
            async let prefs = repository.loadSettings()
            let (s, p) = try await (snap, prefs)
            apply(s, p)
            if let id = try? await Backend.client.auth.session.user.id.uuidString { SnapshotCache.save(s, p, for: id) }
            if let loaded = try? await repository.loadOrderItems() { orderItems = loaded; recompute() }
            await pruneDuplicateWatches()
            return true
        } catch {
            if error is CancellationError { return false }                  // the caller went away; nothing to say
            log.error("reload failed: \(error.localizedDescription, privacy: .public)")
            // One quiet retry covers token-refresh clock skew ("JWT issued at future") and a dropped connection.
            if retry { try? await Task.sleep(for: .seconds(2)); return await reload(retry: false) }
            report(error)
            return false
        }
    }

    /// The Link button: offer Wallet next to banks where it exists and isn't linked yet, else straight to Plaid.
    func startLink() {
        if walletAvailable, !walletLinked { showLinkOptions = true } else { Task { await link() } }
    }

    /// Asks for Wallet access; a yes reads Apple Card / Apple Cash / Savings and sends them up before the reload.
    func linkWallet() async {
        guard !isLinking else { return }
        isLinking = true; defer { isLinking = false }
        let wallet = wallet
        do {
            if try await withDeadline(120, { try await wallet.connect() }) {
                walletLinked = true; walletAccessLost = false; WalletSource.setBackgroundDelivery(true)
                if onboarding == .link { onboarding = .reading }
                await reload(); await onboardingRead()
            }
            else { errorMessage = "Poise doesn't have access to Wallet. You can allow it in Settings → Apps → Poise." }
        } catch { report(error) }
    }

    /// Reads Wallet's changes since last time and uploads them. Returns true when something changed.
    @discardableResult
    func syncWallet() async -> Bool {
        guard walletLinked, WalletSource.isAvailable else { return false }
        let wallet = wallet
        do {
            let summary = try await withDeadline(90, { try await wallet.sync() })
            walletAccessLost = false
            return summary.accounts > 0
        } catch {
            log.error("wallet sync failed: \(error.localizedDescription, privacy: .public)")
            if await !wallet.isAuthorized() { walletAccessLost = true }
            return false
        }
    }

    // MARK: Amazon

    /// Reads Amazon's payments page and writes every order number it can pair onto a charge.
    ///
    /// `deep` is the first connection, which walks back far enough to cover the history Poise already holds; a routine
    /// check reads one page, which is about three weeks. Returns how many charges gained an order.
    @discardableResult
    func syncAmazon(deep: Bool = false, maxPages: Int? = nil, items: Int? = nil) async -> Int {
        guard !amazonReading else { return 0 }
        amazonReading = true; amazonProgress = 0; amazonReadingBackTo = nil
        defer { amazonReading = false; amazonProgress = 0; amazonReadingBackTo = nil }
        let source = AmazonSource.shared
        do {
            let orders = try await source.read(back: earliest(deep: deep), maxPages: maxPages ?? (deep ? 40 : 3),
                                               onPage: { [weak self] pages, oldest in
                                                   self?.amazonProgress = 1 - pow(0.7, Double(pages))
                                                   self?.amazonReadingBackTo = oldest
                                               })
            amazonProgress = 1
            let paired = AmazonOrders.match(orders, to: raw)
            let fresh = paired.filter { id, ref in raw.first { $0.id == id }?.orderRef != ref }
            for (id, ref) in fresh { if let i = raw.firstIndex(where: { $0.id == id }) { raw[i].orderRef = ref } }
            if !fresh.isEmpty { recompute() }
            amazonOrdersRead = source.ordersRead; amazonPagesRead = source.pagesRead; amazonReachedBack = source.reachedBack
            amazonConnected = true; source.isConnected = true
            // Orders came back, so the session works. Anything that goes wrong from here is found by the phase that
            // reads them, which can tell a sign-in page from the end of a list.
            amazonLapsed = source.hasLapsed; amazonCheckedAt = source.lastChecked
            let saved = await repository.setOrderRefs(fresh)
            // Then the second phase, with the session warm: what was in each of them. A check the user asked for reads
            // the lot; a background wake takes a couple, because it only has seconds.
            await fetchAllItems(limit: deep ? nil : (items ?? 2))
            return saved
        } catch AmazonSource.Failure.signedOut {
            amazonLapsed = true
            return 0
        } catch {
            log.error("amazon read failed: \(error.localizedDescription, privacy: .public)")
            return 0
        }
    }

    /// How far back a read needs to go: to the oldest Amazon charge still without an order, so a connection that fell
    /// behind catches up in one pass and a routine check stays short. A background check never looks past a month.
    private func earliest(deep: Bool) -> Date? {
        let month = Calendar.current.date(byAdding: .day, value: -30, to: .now)
        guard deep else { return month }
        let missing = raw.filter { $0.merchantKey.hasPrefix("amazon") && $0.orderRef == nil }.map(\.displayDate).min()
        guard let missing else { return month }
        return max(missing, Calendar.current.date(byAdding: .day, value: -400, to: .now) ?? missing)
    }

    /// What was in the order behind a charge, if it's been read.
    func items(for t: PoiseKit.Transaction) -> AmazonOrderDetail? {
        t.orderRef.flatMap { orderItems[$0] }
    }

    /// Where a merchant says a return has got to, for the charge behind a watch. Amazon prints it on the order page —
    /// "Return started", and what happens next — so a refund in hand needn't look the same as one gone quiet, and the
    /// user needn't be the one to say which.
    func returnProgress(for watch: Watch) -> (status: String, note: String?)? {
        guard let id = watch.transactionID,
              let ref = raw.first(where: { $0.id == id })?.orderRef,
              let detail = orderItems[ref], let status = detail.returnStatus else { return nil }
        return (status, detail.returnNote)
    }

    /// True while the merchant says the return is under way; a watch like that isn't late, it's in progress.
    func returnUnderWay(_ watch: Watch) -> Bool {
        guard let id = watch.transactionID,
              let ref = raw.first(where: { $0.id == id })?.orderRef,
              let detail = orderItems[ref] else { return false }
        return detail.returnStatus != nil && detail.returnInProgress
    }

    /// What a charge bought, short enough for a feed row: one name, or the first two and a count of the rest.
    func contents(of t: PoiseKit.Transaction) -> String? {
        guard let detail = items(for: t), !detail.items.isEmpty else { return nil }
        let names = detail.items.map(\.shortName)
        switch names.count {
        case 1: return names[0]
        case 2: return names.joined(separator: ", ")
        default: return "\(names[0]), \(names[1]) + \(names.count - 2) more"
        }
    }

    func fetchItems(for t: PoiseKit.Transaction) async {
        guard let ref = t.orderRef else { return }
        await fetchItems(ref: ref)
    }

    /// Opens one order's page and reads its contents.
    @discardableResult
    func fetchItems(ref: String) async -> Bool {
        guard needsReading(ref), !fetchingItems.contains(ref), amazonConnected, !amazonLapsed else { return false }
        fetchingItems.insert(ref); defer { fetchingItems.remove(ref) }
        do {
            guard let detail = try await AmazonSource.shared.readItems(for: ref) else { return false }
            orderItems[ref] = detail
            recompute()
            guard let userID = try? await Backend.client.auth.session.user.id.uuidString else { return true }
            try await repository.save(detail, userID: userID)
            return true
        } catch AmazonSource.Failure.signedOut {
            amazonLapsed = true
        } catch {
            log.error("amazon items failed for \(ref, privacy: .public): \(error.localizedDescription, privacy: .public)")
        }
        return false
    }

    /// An order wants reading if it has never been read, or was read before Poise started keeping the day it was
    /// placed — which is the day the charge belongs on.
    private func needsReading(_ ref: String) -> Bool {
        guard let detail = orderItems[ref] else { return true }
        if detail.placed == nil { return true }
        // A return moves: started, received, refunded. While a watch is open on that charge, keep it current.
        return raw.contains { t in
            t.orderRef == ref && watches.contains { w in w.kind == .refund && w.transactionID == t.id && w.status.isOpen }
        }
    }

    /// Reads what was in every order that hasn't been read yet, newest first.
    ///
    /// Amazon has no bulk view of this — it's a page load per order — so this is the slow half of a check and reports
    /// its own progress rather than pretending to be instant. A pause between orders keeps the site from throttling.
    /// `limit` caps it for the background wake, which only has seconds.
    func fetchAllItems(limit: Int? = nil) async {
        guard amazonConnected, !amazonLapsed else {
            log.error("amazon item phase skipped — connected=\(self.amazonConnected, privacy: .public) lapsed=\(self.amazonLapsed, privacy: .public)")
            return
        }
        var newest: [String: Date] = [:]
        for t in raw {
            guard let ref = t.orderRef, needsReading(ref) else { continue }
            newest[ref] = max(newest[ref] ?? .distantPast, t.displayDate)
        }
        var refs = newest.keys.sorted { (newest[$0] ?? .distantPast) > (newest[$1] ?? .distantPast) }
        if let limit { refs = Array(refs.prefix(limit)) }
        guard !refs.isEmpty else { return }

        amazonItemsTotal = refs.count; amazonItemsDone = 0
        defer { amazonItemsTotal = 0; amazonItemsDone = 0 }
        var read = 0
        for ref in refs {
            if Task.isCancelled || amazonLapsed { break }
            if await fetchItems(ref: ref) { read += 1 }
            amazonItemsDone += 1
            try? await Task.sleep(for: .milliseconds(1500))         // a person's pace, not a crawler's
        }
        amazonItemsRead = read
        amazonItemsWanted = refs.count
        amazonItemsFailure = read < refs.count ? AmazonSource.shared.lastItemFailure : nil
        log.info("amazon items: read \(read, privacy: .public) of \(refs.count, privacy: .public)")
    }

    /// Starts the full read and lets go of it. Signing in is the only part that needs the user; everything after is
    /// Poise's problem, and it carries on while they get on with something else.
    func startAmazonSweep() {
        guard !amazonReading else { return }
        amazonSweep = Task { [weak self] in
            await self?.syncAmazon(deep: true)
            self?.amazonSweep = nil
        }
    }

    /// A shallow Amazon check, skipped if one ran recently. Pull-to-refresh and the background task both come here, so
    /// neither can hammer a page that throttles.
    @discardableResult
    func syncAmazonIfDue(notBefore seconds: TimeInterval, maxPages: Int? = nil, items: Int? = nil) async -> Int {
        guard amazonConnected, !amazonReading else { return 0 }
        // A session Amazon has dropped is still worth trying now and then — it may have let us back in, and one page
        // load settles it — but not on every pull, which would be a slow wait for a known answer.
        let gate = amazonLapsed ? max(seconds, 6 * 3600) : seconds
        if let last = amazonCheckedAt, Date.now.timeIntervalSince(last) < gate { return 0 }
        return await syncAmazon(maxPages: maxPages, items: items)
    }

    /// Forgets the session and every order number it found. The charges themselves are untouched.
    func disconnectAmazon() async {
        await AmazonSource.shared.disconnect()
        amazonConnected = false; amazonLapsed = false; amazonCheckedAt = nil
        for i in raw.indices where raw[i].orderRef != nil { raw[i].orderRef = nil }
        recompute()
        do { try await repository.clearOrderRefs() } catch { report(error) }
    }

    /// Everything the screens read, from a fresh load or the cache.
    private func apply(_ s: Repository.Snapshot, _ p: Repository.Settings) {
        accounts = s.accounts
        hiddenAccounts = s.hiddenAccounts
        raw = s.transactions
        lastSync = s.lastSync
        institutions = s.institutions
        relinkNeeded = s.relinkNeeded
        statementConsentNeeded = s.statementConsentNeeded
        walletLinked = s.walletLinked
        settings = p
        customCategories = s.customCategories
        watches = s.watches
        rebuildCategories()
        recompute()
        if hasLinkedBank, !rememberedLinked { rememberedLinked = true; UserDefaults.standard.set(true, forKey: "hasLinkedBefore") }
    }

    /// Opens Plaid Link; on success the server has already run the first sync, so a reload shows real rows.
    func link() async {
        guard !isLinking else { return }
        isLinking = true; defer { isLinking = false }
        do {
            let linker = self.linker ?? BankLinker(client: Backend.client)
            self.linker = linker
            if try await linker.link() != nil { if onboarding == .link { onboarding = .reading }; await reload(); await onboardingRead() }
        } catch {
            report(error)
        }
    }

    /// Repairs a broken bank login (Plaid Link update mode), then marks the item healthy server-side.
    func relink(_ item: Repository.Item) async {
        guard !isLinking else { return }
        isLinking = true; defer { isLinking = false }
        do {
            let linker = self.linker ?? BankLinker(client: Backend.client)
            self.linker = linker
            if try await linker.link(relink: item.id) != nil { await refresh(trigger: "relink", force: true) }
        } catch { report(error) }
    }

    /// Takes the user back through Link to allow a product the bank was never given permission to share — card due
    /// dates and statement balances, which is what Next is missing without them.
    func grantStatementAccess(_ item: Repository.Item) async {
        guard !isLinking else { return }
        isLinking = true; defer { isLinking = false }
        do {
            let linker = self.linker ?? BankLinker(client: Backend.client)
            self.linker = linker
            guard try await linker.link(relink: item.id, consent: true) != nil else { return }
            await refresh(trigger: "consent", force: true)
            // Plaid can take a moment to attach a product it has only just been granted, and the first read after
            // Allow often still says it isn't permitted. One quiet retry turns "nothing happened" into the due dates
            // appearing by themselves.
            if statementConsentNeeded.contains(where: { $0.id == item.id }) {
                try? await Task.sleep(for: .seconds(4))
                await refresh(trigger: "consent-retry", force: true)
            }
        } catch { report(error) }
    }

    func readSession() async {
        let session = try? await Backend.client.auth.session
        isAnonymous = session?.user.isAnonymous ?? true
        accountName = (session?.user.userMetadata["full_name"]?.stringValue).flatMap { $0.isEmpty ? nil : $0 } ?? session?.user.email
    }

    // MARK: account

    @discardableResult
    func signInWithApple(_ credential: ASAuthorizationAppleIDCredential, nonce: String) async -> Bool {
        do {
            try await Auth.signIn(with: credential, nonce: nonce, client: Backend.client)
            await readSession()
            await reload()
            return true
        } catch { report(error); return false }
    }

    // MARK: onboarding

    func advanceOnboarding(to step: OnboardingStep) { onboarding = step }

    /// Signed in from the welcome screen: an account that already has banks skips straight to Home.
    func onboardingSignedIn() {
        guard onboarding == .welcome else { return }
        if hasLinkedBank { finishOnboarding() } else { onboarding = .link }
    }

    /// The reading screen gets a beat after the first load, then the payday we spotted (or the ask to set one).
    private func onboardingRead() async {
        guard onboarding == .reading else { return }
        try? await Task.sleep(for: .seconds(1.5))
        guard onboarding == .reading else { return }
        onboarding = .payday
    }

    func finishOnboarding() {
        UserDefaults.standard.set(true, forKey: "onboardingDone")
        onboarding = nil
    }

    func signOut() async {
        try? await Backend.client.auth.signOut()
        resetState()
        await start()
    }

    /// Revokes every bank connection and deletes the user server-side, then starts over as a fresh anonymous user.
    func deleteEverything() async {
        do {
            try await Backend.client.functions.invoke("delete-account")
            try? await Backend.client.auth.signOut()
            UserDefaults.standard.removeObject(forKey: "acknowledgedInsights")
            acknowledged = []
            resetState()
            await start()
        } catch { report(error) }
    }

    private func resetState() {
        accounts = []; hiddenAccounts = []; raw = []; transactions = []; streams = []; allStreams = []; endedStreams = []; verdict = nil; pace = nil; cashflow = []; insights = []; reviewCards = []; priceItems = []
        lastSync = nil; institutions = []; relinkNeeded = []; statementConsentNeeded = []; walletLinked = false; walletAccessLost = false; settings = Repository.Settings(); isAnonymous = true; accountName = nil
        customCategories = []; watches = []; categories = .builtIn
        rememberedLinked = false; UserDefaults.standard.removeObject(forKey: "hasLinkedBefore"); UserDefaults.standard.removeObject(forKey: "onboardingDone")
        onboarding = nil
        SnapshotCache.clear()
        WalletSource.setBackgroundDelivery(false)
    }

    /// Everything Poise holds about the user, as one JSON file for the share sheet.
    func exportFile() throws -> URL {
        struct Export: Encodable { let exportedAt: Date; let accounts: [Account]; let transactions: [PoiseKit.Transaction]; let streams: [RecurringStream] }
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]; encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(Export(exportedAt: .now, accounts: allAccounts, transactions: transactions, streams: streams))
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("poise-export-\(Date.now.formatted(.iso8601.year().month().day())).json")
        try data.write(to: url, options: .atomic)
        return url
    }

    // MARK: lock

    func unlock() async {
        guard isLocked else { return }
        if await Auth.authenticate() { isLocked = false }
    }

    /// App came to the foreground: refresh if the last one is older than the policy allows (15 min), else just reload.
    func becameActive() async {
        rollDay()
        await refreshPushStatus()
        if settings.faceID, !isLocked { isLocked = true; await unlock() }
        guard hasLinkedBank else { return }
        if let last = lastForegroundRefresh, Date.now.timeIntervalSince(last) < 15 * 60 { await reload(); return }
        lastForegroundRefresh = .now
        await refresh(trigger: "foreground")
    }

    #if DEBUG
    /// `-stale-day`: draw the screens against yesterday, the way an app left open overnight would.
    func pretendYesterday() { today = Calendar.current.date(byAdding: .day, value: -1, to: today) ?? today }
    #endif

    /// Midnight: everything dated relative to "today" moves on — the feed's headers, the cash-flow walk, the month's pace.
    func rollDay() {
        let day = Calendar.current.startOfDay(for: .now)
        if day != today { today = day; recompute() }
        midnight?.cancel()
        guard let next = Calendar.current.date(byAdding: .day, value: 1, to: day) else { return }
        midnight = Task { [weak self] in
            try? await Task.sleep(for: .seconds(max(1, next.timeIntervalSinceNow + 1)))
            guard !Task.isCancelled else { return }
            self?.rollDay()
        }
    }

    /// Foreground / pull-to-refresh: fresh balances now, and the banks asked for anything new.
    /// Wallet has no webhook, so its changes are read and sent right here.
    /// `force` skips the per-bank rate limit. Anything the user just did — repairing a login, allowing a product — has
    /// to take effect now; waiting out the limit is what made allowing card statements feel like it hadn't worked.
    func refresh(trigger: String = "pull", force: Bool = false) async {
        #if DEBUG
        // `-slow-refresh` holds a pull open the way a real sync does, so layout bugs that only appear during it show up.
        if ProcessInfo.processInfo.arguments.contains("-slow-refresh") { try? await Task.sleep(for: .seconds(4)) }
        #endif
        let before = try? await repository.bankSyncedAt()
        let asked = await refreshBanks(trigger: trigger, force: force)
        // The pull lets go as soon as what's already stored is on screen: the hourly refresh keeps that within the
        // hour. What the banks send now lands a few seconds later through their webhooks — Chase in about five, Barclays
        // in about twenty — and each one slides in as it arrives. Wallet and Amazon do the same on their own time.
        await reload()
        if asked { followDeliveries(after: before) }
        Task { if await syncWallet() { await reload() } }
        Task { if await syncAmazonIfDue(notBefore: 2 * 60, maxPages: 3, items: 8) > 0 { await reload() } }
    }

    /// iOS's wake, about once an hour: ask the banks, give their webhooks a moment, and leave the newest snapshot cached,
    /// so the next open already has it and the next pull has little left to fetch.
    func backgroundRefresh() async {
        // Only with the session already on this phone. `ensureSession` would sign in someone new if the keychain
        // couldn't be read, and a locked phone is exactly when it can't.
        guard (try? await Backend.client.auth.session) != nil else { return }
        let before = try? await repository.bankSyncedAt()
        if await refreshBanks(trigger: "background") {
            let end = ContinuousClock.now + .seconds(20)
            while ContinuousClock.now < end, !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2))
                if let at = try? await repository.bankSyncedAt(), at > (before ?? .distantPast) { break }
            }
        }
        _ = await reload(retry: false)
    }

    /// True if any bank was actually asked; ones refreshed in the last 15 minutes are skipped and send nothing.
    private func refreshBanks(trigger: String, force: Bool = false) async -> Bool {
        struct Body: Encodable { let trigger: String; let force: Bool }
        struct Result: Decodable { let results: [String: String] }
        let r: Result? = try? await Backend.client.functions.invoke("refresh", options: FunctionInvokeOptions(body: Body(trigger: trigger, force: force)))
        return r?.results.values.contains("refreshed") ?? false
    }

    /// Reloads each time a bank delivers, for a minute after it was asked. Banks answer one by one, seconds apart.
    private func followDeliveries(after before: Date?) {
        lateDelivery?.cancel()
        lateDelivery = Task { [weak self] in
            var last = before ?? .distantPast
            let end = ContinuousClock.now + .seconds(60)
            while ContinuousClock.now < end {
                try? await Task.sleep(for: .seconds(2))
                guard let self, !Task.isCancelled else { return }
                if let at = try? await self.repository.bankSyncedAt(), at > last { last = at; await self.reload() }
            }
        }
    }

    // MARK: corrections

    func correct(_ t: PoiseKit.Transaction, kind: TransactionKind, categoryID: String?, always: Bool) async {
        guard let i = raw.firstIndex(where: { $0.id == t.id }) else { return }
        raw[i].kind = kind; raw[i].categoryID = categoryID; raw[i].pairID = nil
        var ids = [t.id]
        if always {
            // The rule names what the merchant is; each row's direction still decides spend vs refund.
            for j in raw.indices where raw[j].merchantKey == t.merchantKey && raw[j].id != t.id && raw[j].kind != .income {
                let sameWay = raw[j].isOutflow == t.isOutflow
                let k: TransactionKind = sameWay ? kind : (kind == .spend ? .refund : kind == .refund ? .spend : kind)
                raw[j].kind = k; raw[j].categoryID = categoryID; raw[j].pairID = nil
                if sameWay { ids.append(raw[j].id) } else { Task { try? await repository.update(transactionID: raw[j].id, kind: k, categoryID: categoryID) } }
            }
        }
        recompute()
        do {
            if always { try await repository.upsertRule(merchant: t.merchant, kind: kind, categoryID: categoryID, applyTo: ids) }
            else { try await repository.update(transactionID: t.id, kind: kind, categoryID: categoryID) }
        } catch { report(error) }
    }

    // MARK: categories

    private func rebuildCategories() {
        let overridden = SpendCategory.allCases.map { c -> PoiseKit.Category in var cat = PoiseKit.Category.builtIn(c); if let l = settings.categoryLens[c.rawValue].flatMap(Lens.init(rawValue:)) { cat.lens = l }; return cat }
        categories = CategorySet(overridden + customCategories)
    }

    /// New category; optional merchants move now and become rules for everything after.
    func createCategory(name: String, symbol: String, lens: Lens, startWith merchants: [String]) async -> PoiseKit.Category? {
        do {
            let c = try await repository.create(category: name, symbol: symbol, lens: lens)
            customCategories.append(c); rebuildCategories()
            for m in merchants {
                let key = PoiseKit.Transaction.merchantKey(m)
                var ids: [String] = []
                for j in raw.indices where raw[j].merchantKey == key && (raw[j].kind == .spend || raw[j].kind == .untracked) { raw[j].categoryID = c.id; ids.append(raw[j].id) }
                try await repository.upsertRule(merchant: m, kind: .spend, categoryID: c.id, applyTo: ids)
            }
            recompute()
            return c
        } catch { report(error); return nil }
    }

    func updateCategory(_ c: PoiseKit.Category) async {
        if c.builtIn {
            var s = settings; s.categoryLens[c.id] = c.lens.rawValue; await save(s); rebuildCategories(); recompute()
        } else {
            if let i = customCategories.firstIndex(where: { $0.id == c.id }) { customCategories[i] = c }
            rebuildCategories(); recompute()
            do { try await repository.update(category: c) } catch { report(error) }
        }
    }

    func deleteCategory(_ c: PoiseKit.Category) async {
        guard !c.builtIn else { return }
        customCategories.removeAll { $0.id == c.id }
        for j in raw.indices where raw[j].categoryID == c.id { raw[j].categoryID = SpendCategory.other.rawValue }
        rebuildCategories(); recompute()
        do { try await repository.delete(categoryID: c.id) } catch { report(error) }
    }

    // MARK: watches

    /// Clears up refund watches that doubled up on one charge while the old matching rule was closing them wrongly.
    /// The first one made is kept — it carries the real history — and the extras go.
    private func pruneDuplicateWatches() async {
        var seen = Set<String>()
        var extras: [Watch] = []
        for w in watches.filter({ $0.kind == .refund }).sorted(by: { $0.createdAt < $1.createdAt }) {
            guard let id = w.transactionID else { continue }
            if seen.contains(id) { extras.append(w) } else { seen.insert(id) }
        }
        for w in extras { await removeWatch(w) }
    }

    /// "It arrived" — the fallback for a refund Poise can't see the end of: store credit, a gift card, a partial
    /// amount, or money back to a card that isn't linked. Everything it can see, it closes on its own.
    func markWatchArrived(_ w: Watch) async {
        var out = w
        out.status = .arrived
        out.resolvedAt = .now
        out.resolvedTransactionID = nil
        await updateWatch(out)
    }

    func addWatch(_ w: Watch) async {
        // One refund watch per charge, whatever state the old one is in. A watch wrongly marked arrived used to let a
        // second be made for the same charge, and both then sat in the list waiting on the same money.
        if w.kind == .refund, let id = w.transactionID, watches.contains(where: { $0.kind == .refund && $0.transactionID == id }) { return }
        watches.insert(w, at: 0); recompute()
        do { try await repository.insert(watch: w) } catch { report(error) }
    }

    func updateWatch(_ w: Watch) async {
        if let i = watches.firstIndex(where: { $0.id == w.id }) { watches[i] = w }
        recompute()
        do { try await repository.update(watch: w) } catch { report(error) }
    }

    func closeWatch(_ w: Watch) async { var c = w; c.status = .closed; c.resolvedAt = .now; await updateWatch(c) }

    func removeWatch(_ w: Watch) async {
        watches.removeAll { $0.id == w.id }; recompute()
        do { try await repository.delete(watchID: w.id) } catch { report(error) }
    }

    /// Statuses the engine changed (refund arrived, overdue, merchant charged again) are written back so the server and pushes agree.
    private func persistWatchChanges(from before: [Watch]) {
        let changed = watches.filter { w in before.first { $0.id == w.id }?.status != w.status }
        guard !changed.isEmpty else { return }
        Task { for w in changed { try? await repository.update(watch: w) } }
    }

    func setRole(_ role: AccountRole, for account: Account) async {
        if let i = accounts.firstIndex(where: { $0.id == account.id }) { accounts[i].role = role; recompute() }
        else if let i = hiddenAccounts.firstIndex(where: { $0.id == account.id }) { hiddenAccounts[i].role = role }
        else { return }
        do { try await repository.update(accountID: account.id, role: role) } catch { report(error) }
    }

    /// Hide: the account and its rows leave every number now; the flag is the user's alone, so no sync undoes it.
    /// Show: it comes straight back, history included — nothing was deleted.
    func setHidden(_ hidden: Bool, for account: Account) async {
        guard account.hidden != hidden else { return }
        var moved = account; moved.hidden = hidden; moved.hiddenAt = hidden ? .now : nil
        accounts.removeAll { $0.id == account.id }; hiddenAccounts.removeAll { $0.id == account.id }
        if hidden { hiddenAccounts.append(moved); raw.removeAll { $0.accountID == account.id }; recompute() }
        else { accounts.append(moved) }
        do {
            try await repository.update(accountID: account.id, hidden: hidden)
            if !hidden { await reload() }                       // its transactions are fetched again
        } catch { report(error); await reload() }
    }

    /// Removes one institution entirely — revoked at the provider, accounts and history gone.
    func disconnect(itemID: String) async {
        do {
            try await repository.disconnect(itemID: itemID)
            await reload()
            if !walletLinked { WalletSource.setBackgroundDelivery(false) }
        } catch { report(error) }
    }

    func save(_ s: Repository.Settings) async {
        settings = s; recompute()
        do { try await repository.save(s) } catch { report(error) }
    }

    /// Every insight goes somewhere: a charge (with its why-card), a subscription, the watch list, or the tab that explains it.
    func open(_ insight: Insight) {
        switch insight.kind {
        case .duplicate, .fee:
            let txnID = String(insight.id.drop(while: { $0 != "-" }).dropFirst())
            if let t = transactions.first(where: { $0.id == txnID }) { insightContext = insight; selectedTransaction = t } else { tab = .leaks }
        case .priceUp, .renewal, .newStream:
            if let s = streams.first(where: { insight.id.hasPrefix("price-\($0.id)") || insight.id.hasPrefix("renewal-\($0.id)") || insight.id.hasPrefix("new-\($0.id)") }) { selectedStream = s } else { tab = .leaks }
        case .priceMoved:
            if let item = priceItems.first(where: { insight.id.hasPrefix("price-item-\($0.id)-") }) { selectedPriceItem = .init(id: item.id) } else { showPricesList() }
        case .cancelledCharge:
            if let s = allStreams.first(where: { insight.id.hasPrefix("cancelled-\($0.id)-") }) { selectedStream = s } else { tab = .leaks }
        case .streamReturned:
            if let s = streams.first(where: { insight.id.hasPrefix("returned-\($0.id)-") }) { selectedStream = s } else { tab = .leaks }
        case .categoryOver:
            // "category-over-<id>-<year>-<month>" → the category's own page.
            let rest = insight.id.dropFirst("category-over-".count)
            let id = rest.split(separator: "-").dropLast(2).joined(separator: "-")
            whereMode = .spending; tab = .whereTab; wherePath = [id]
        case .watchTriggered, .refundOverdue, .refundArrived: tab = .home; showWatching = true
        case .crunch, .statement: tab = .next14
        case .paceOverrun, .positive: tab = .pace
        }
    }

    /// The earlier half of a "charged twice": same merchant, same amount, within two days before.
    func duplicatePartner(of t: PoiseKit.Transaction) -> PoiseKit.Transaction? {
        transactions.filter { $0.id != t.id && $0.merchantKey == t.merchantKey && $0.amount == t.amount && $0.displayDate <= t.displayDate }
            .filter { abs(Calendar.current.dateComponents([.day], from: $0.displayDate, to: t.displayDate).day ?? 99) <= 2 }
            .max { $0.displayDate < $1.displayDate }
    }

    /// The charges behind a stream, newest first, last twelve months.
    func charges(for s: RecurringStream) -> [PoiseKit.Transaction] {
        let since = Calendar.current.date(byAdding: .year, value: -1, to: .now) ?? .distantPast
        let ids = Set(s.transactionIDs)
        return transactions.filter { (ids.isEmpty ? "\($0.kind.rawValue)|\($0.merchantKey)" == s.id : ids.contains($0.id)) && $0.displayDate >= since }.sorted { $0.displayDate > $1.displayDate }
    }

    /// "I cancelled this": the stream stops counting from that date; a later charge from the merchant is the top leak.
    func cancel(_ s: RecurringStream, on date: Date) async {
        var draft = settings; draft.cancelledStreams[s.id] = Calendar.current.startOfDay(for: date)
        await save(draft)
    }

    func uncancel(_ s: RecurringStream) async {
        var draft = settings; draft.cancelledStreams[s.id] = nil
        await save(draft)
    }

    func isCancelled(_ s: RecurringStream) -> Date? { settings.cancelledStreams[s.id] }

    /// The repeating stream a charge belongs to, if it belongs to one — a stream filed as "just purchases" included,
    /// so the charge sheet can show that choice and undo it.
    func stream(containing t: PoiseKit.Transaction) -> RecurringStream? {
        allStreams.first { $0.kind != .income && $0.transactionIDs.contains(t.id) }
    }

    /// What a stream is for: the category of its newest charge. Separate from whether it's a subscription or a bill.
    /// The merchant's newest logo, so a stream wears the same face as its charges.
    func logoURL(for s: RecurringStream) -> String? { logos[PoiseKit.Transaction.merchantKey(s.merchant)] }

    func categoryID(for s: RecurringStream) -> String? {
        s.transactionIDs.last.flatMap { id in raw.first { $0.id == id } }?.categoryID
    }

    /// Files a stream under a category — every charge from that merchant, and the ones still to come.
    func file(_ s: RecurringStream, under categoryID: String) async {
        guard let id = s.transactionIDs.last, let t = raw.first(where: { $0.id == id }) else { return }
        await correct(t, kind: t.kind == .refund ? .refund : .spend, categoryID: categoryID, always: true)
    }

    /// "This is a…": subscription or bill by hand, or "just purchases" (dismissed — out of Leaks and Next 14).
    func setStreamKind(_ s: RecurringStream, _ kind: StreamKind?) async {
        var draft = settings
        if let kind {
            draft.streamKinds[s.id] = kind.rawValue
            draft.dismissedStreams.removeAll { $0 == s.id }
        } else {
            draft.streamKinds[s.id] = nil
            if !draft.dismissedStreams.contains(s.id) { draft.dismissedStreams.append(s.id) }
        }
        await save(draft)
    }

    /// A stream bills like a plan when it isn't a burrito that happens to land monthly: anything but the everyday
    /// built-in categories (dining, fun, shopping, groceries, transport, health).
    func isPlanLike(_ s: RecurringStream) -> Bool {
        guard s.kind != .income else { return false }
        let everyday: Set<String> = ["dining", "fun", "shopping", "groceries", "transport", "health"]
        let categoryID = s.transactionIDs.last.flatMap { id in transactions.first { $0.id == id } }?.categoryID
        let c = categories.resolve(categoryID)
        return !(c.builtIn && everyday.contains(c.id))
    }

    struct Usage: Sendable { var thisMonth: Decimal; var count: Int; var lastMonth: Decimal }
    /// A plan's pay-as-you-go: the merchant's other charges this month (and last), outside the stream's own rows.
    func usage(for s: RecurringStream) -> Usage? {
        guard isPlanLike(s) else { return nil }
        let key = PoiseKit.Transaction.merchantKey(s.merchant), own = Set(s.transactionIDs)
        let cal = Calendar.current
        guard let month = cal.dateInterval(of: .month, for: .now), let prev = cal.date(byAdding: .month, value: -1, to: month.start).flatMap({ cal.dateInterval(of: .month, for: $0) }) else { return nil }
        let extra = transactions.filter { ($0.kind == .spend || $0.kind == .untracked) && $0.amount < 0 && !$0.excluded && $0.merchantKey == key && !own.contains($0.id) }
        let now = extra.filter { month.holds($0.displayDate) }, last = extra.filter { prev.holds($0.displayDate) }
        guard !now.isEmpty || !last.isEmpty else { return nil }
        return Usage(thisMonth: now.reduce(0) { $0 + $1.magnitude }, count: now.count, lastMonth: last.reduce(0) { $0 + $1.magnitude })
    }

    /// "Heads-up before it renews" = a merchant watch on the stream; the next charge becomes a heads-up.
    func setRenewalHeadsUp(_ on: Bool, for s: RecurringStream) async {
        let key = PoiseKit.Transaction.merchantKey(s.merchant)
        let existing = watches.first { $0.kind == .merchant && $0.matcher == key && $0.status.isOpen }
        if on, existing == nil { await addWatch(Watch(kind: .merchant, merchant: s.merchant)) }
        else if !on, let existing { await removeWatch(existing) }
    }

    /// "Not a subscription": the detector keeps finding it; the user stops seeing it.
    func dismiss(_ s: RecurringStream) async {
        var draft = settings
        if !draft.dismissedStreams.contains(s.id) { draft.dismissedStreams.append(s.id) }
        selectedStream = nil
        await save(draft)
    }

    // MARK: what was this

    /// A name for the charge — and, with `always`, for every charge from that merchant (a rule, applied at read time).
    func rename(_ t: PoiseKit.Transaction, to name: String?, always: Bool) async {
        let clean = name?.trimmingCharacters(in: .whitespacesAndNewlines)
        let value = (clean?.isEmpty ?? true) ? nil : clean
        if always {
            for i in raw.indices where raw[i].merchantKey == t.merchantKey { raw[i].displayName = value }
        } else if let i = raw.firstIndex(where: { $0.id == t.id }) { raw[i].displayName = value }
        recompute()
        do {
            if always { try await repository.setDisplayName(merchant: t.merchant, name: value) }
            else { try await repository.update(transactionID: t.id, displayName: value) }
        } catch { report(error) }
    }

    func setNote(_ t: PoiseKit.Transaction, note: String?) async {
        let clean = note?.trimmingCharacters(in: .whitespacesAndNewlines)
        let value = (clean?.isEmpty ?? true) ? nil : clean
        if let i = raw.firstIndex(where: { $0.id == t.id }) { raw[i].note = value }
        recompute()
        do { try await repository.update(transactionID: t.id, note: value) } catch { report(error) }
    }

    /// A card's name, finish and chip. Nil for any goes back to the bank's name, Poise's pick, or the finish's own chip.
    func setLook(nickname: String?, finish: CardFinish?, chip: CardChipMetal?, for account: Account) async {
        let trimmed = nickname?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let name = trimmed.isEmpty || trimmed == account.bankName ? nil : String(trimmed.prefix(40))
        // Picking the finish Poise would have picked anyway isn't a choice worth storing; the default can still move.
        let pick = finish == CardFinish.defaults(for: cards)[account.id] ? nil : finish
        // Same for the chip: the one the finish comes with follows the finish if it changes later.
        let metal = chip == (finish ?? self.finish(for: account)).chip ? nil : chip
        if let i = accounts.firstIndex(where: { $0.id == account.id }) {
            accounts[i].nickname = name; accounts[i].finish = pick?.rawValue; accounts[i].chip = metal?.rawValue
            accounts[i].name = name ?? accounts[i].bankName ?? accounts[i].name
        }
        recompute()
        do { try await repository.update(accountID: account.id, nickname: name, finish: pick?.rawValue, chip: metal?.rawValue) } catch { report(error) }
    }

    /// How one card gets paid, which is the only thing that decides what Next subtracts on its due date.
    func setPayment(_ pays: CardPayment?, fixedAmount: Decimal? = nil, for account: Account) async {
        if let i = accounts.firstIndex(where: { $0.id == account.id }) {
            accounts[i].pays = pays
            accounts[i].paysFixedAmount = fixedAmount
        }
        recompute()
        do { try await repository.update(accountID: account.id, pays: pays, fixedAmount: fixedAmount) } catch { report(error) }
    }

    /// Leave a one-off out of the math. Reversible; the row stays in the feed either way.
    func setExcluded(_ t: PoiseKit.Transaction, _ excluded: Bool) async {
        if let i = raw.firstIndex(where: { $0.id == t.id }) { raw[i].excluded = excluded }
        recompute()
        do { try await repository.update(transactionID: t.id, excluded: excluded) } catch { report(error) }
    }

    // MARK: search & merchants

    /// Merchant, your name for it, the note, the bank's descriptor — or an amount ("14.20", "14").
    func search(_ query: String, account: String? = nil, category: String? = nil, pending: Bool = false, excluded: Bool = false) -> [PoiseKit.Transaction] {
        let q = query.trimmingCharacters(in: .whitespaces)
        let amount = Decimal(string: q.replacingOccurrences(of: "$", with: "").replacingOccurrences(of: ",", with: ""))
        // Searching finds what the feed shows, so a card payment is one result rather than its two halves.
        return feed.filter { t in
            if let account, t.accountID != account { return false }
            if let category, categories.resolve(t.categoryID).id != category || !(t.kind == .spend || t.kind == .untracked) { return false }
            if pending, !t.pending { return false }
            if excluded, !t.excluded { return false }
            if q.isEmpty { return true }
            if let amount, t.magnitude == amount || t.magnitude.money2.contains(q) { return true }
            let hay = [t.displayMerchant, t.merchant, t.note ?? ""].joined(separator: " ")
            return hay.range(of: q, options: [.caseInsensitive, .diacriticInsensitive]) != nil
        }
    }

    /// Everything from one merchant, newest first — charges, refunds, the lot.
    func rows(merchant key: String) -> [PoiseKit.Transaction] {
        transactions.filter { $0.merchantKey == key }.sorted { $0.displayDate > $1.displayDate }
    }

    struct MerchantStats: Sendable { var name: String; var symbol: String; var logoURL: String?; var count: Int; var firstSeen: Date?; var thisMonth: Decimal; var usual: Decimal?; var perCharge: Decimal?; var thisYear: Decimal; var categoryName: String; var categoryID: String? }
    /// This month, the usual month (median of the last six full months that had a charge), the year so far.
    func stats(merchant key: String, now: Date = .now) -> MerchantStats? {
        let all = rows(merchant: key)
        guard let latest = all.first else { return nil }
        let cal = Calendar.current
        let spend = all.filter { ($0.kind == .spend || $0.kind == .untracked) && !$0.excluded }
        let monthStart = cal.date(from: cal.dateComponents([.year, .month], from: now))!
        let yearStart = cal.date(from: cal.dateComponents([.year], from: now))!
        var monthly: [Decimal] = []
        for back in 1...6 {
            guard let start = cal.date(byAdding: .month, value: -back, to: monthStart), let end = cal.date(byAdding: .month, value: 1, to: start) else { continue }
            let total = spend.filter { $0.displayDate >= start && $0.displayDate < end }.reduce(Decimal(0)) { $0 + $1.magnitude }
            if total > 0 { monthly.append(total) }
        }
        let usual: Decimal? = monthly.isEmpty ? nil : monthly.sorted()[monthly.count / 2]
        let cat = categories.resolve(latest.categoryID)
        // The merchant page is the shop, not one named item bought there — Amazon stays Amazon.
        return MerchantStats(name: latest.merchant.prettyMerchant, symbol: cat.symbol, logoURL: all.first { $0.logoURL != nil }?.logoURL, count: all.count, firstSeen: all.last?.displayDate,
                             thisMonth: spend.filter { $0.displayDate >= monthStart }.reduce(0) { $0 + $1.magnitude }.roundedToCents, usual: usual?.roundedToCents,
                             perCharge: spend.isEmpty ? nil : spend.map(\.magnitude).sorted()[spend.count / 2].roundedToCents,
                             thisYear: spend.filter { $0.displayDate >= yearStart }.reduce(0) { $0 + $1.magnitude }.roundedToCents,
                             categoryName: latest.kind == .spend || latest.kind == .untracked ? cat.name : "—", categoryID: latest.kind == .spend ? cat.id : nil)
    }

    /// "Tell me if it charges again", from anywhere a merchant is shown.
    func setMerchantWatch(_ on: Bool, merchant: String) async {
        let key = PoiseKit.Transaction.merchantKey(merchant)
        let existing = watches.first { $0.kind == .merchant && $0.matcher == key && $0.status.isOpen }
        if on, existing == nil { await addWatch(Watch(kind: .merchant, merchant: merchant)) }
        else if !on, let existing { await removeWatch(existing) }
    }

    // MARK: prices

    func priceItem(id: String) -> PriceItem? { priceItems.first { $0.id == id } }

    /// Prices live on the Where tab: switch to it, on the chip asked for.
    func showPricesList(filter: String = "all") { pricesFilter = filter; whereMode = .prices; tab = .whereTab }

    /// The item a charge belongs to: its name's item when it has one, else its merchant's.
    func priceItem(for t: PoiseKit.Transaction) -> PriceItem? {
        priceItems.first { item in item.purchases.contains { $0.id == t.id } }
    }

    /// A category's run of months — every charge it ever had, not just the window in view.
    func history(categoryID: String, now: Date = .now) -> CategoryHistory? {
        CategoryHistoryEngine.history(categoryID: categoryID, transactions: transactions, now: now, categories: categories)
    }

    /// Categories the user asked to hear about when a month runs over.
    func watchesCategory(_ id: String) -> Bool { settings.watchedCategories.contains(id) }
    func setCategoryWatch(_ on: Bool, categoryID: String) async {
        var draft = settings
        if on { if !draft.watchedCategories.contains(categoryID) { draft.watchedCategories.append(categoryID) } }
        else { draft.watchedCategories.removeAll { $0 == categoryID } }
        await save(draft)
    }

    /// What a merchant looks like when it isn't an item: the spread that makes a price meaningless, and what's followed here.
    struct StoreShape: Sendable { var count: Int; var low: Decimal; var high: Decimal; var usual: Decimal }
    func storeShape(merchantKey: String) -> StoreShape? {
        guard priceItems.first(where: { $0.source == .merchant && $0.merchantKey == merchantKey }) == nil else { return nil }
        let rows = transactions.filter { ($0.kind == .spend || $0.kind == .untracked) && $0.amount < 0 && !$0.excluded && $0.merchantKey == merchantKey }
        guard rows.count >= 3, let low = rows.map(\.magnitude).min(), let high = rows.map(\.magnitude).max(), high > low else { return nil }
        let sorted = rows.map(\.magnitude).sorted()
        return StoreShape(count: rows.count, low: low, high: high, usual: sorted[sorted.count / 2])
    }

    /// Items followed from this merchant — named runs whose purchases came from here.
    func itemsFollowed(at merchantKey: String) -> [PriceItem] {
        priceItems.filter { $0.source == .named && $0.purchases.contains { PoiseKit.Transaction.merchantKey($0.merchant) == merchantKey } }
    }

    /// Names already given to charges at this merchant — one tap to name the next purchase the same way.
    func itemNames(at merchantKey: String) -> [String] {
        priceItems.filter { $0.source == .named && $0.purchases.contains { PoiseKit.Transaction.merchantKey($0.merchant) == merchantKey } }.map(\.name)
    }

    /// The Prices list: what moved lately first, then everything else by how often it's bought.
    var pricesMovedLately: [PriceItem] { priceItems.filter { $0.movedLately(now: .now) }.sorted { abs($0.deltaPercent) > abs($1.deltaPercent) } }
    var pricesRest: [PriceItem] { priceItems.filter { !$0.movedLately(now: .now) }.sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending } }

    /// Renames an item: a named run takes the new name on every purchase; a merchant item becomes the merchant's rule.
    func renameItem(_ item: PriceItem, to name: String) async {
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }
        let ids = Set(item.purchases.map(\.id))
        if item.source == .named {
            for i in raw.indices where ids.contains(raw[i].id) { raw[i].displayName = clean }
            recompute()
            for id in ids { do { try await repository.update(transactionID: id, displayName: clean) } catch { report(error); break } }
        } else if let t = transactions.first(where: { ids.contains($0.id) }) {
            await rename(t, to: clean, always: true)
        }
    }

    /// "Tell me when the price moves": a watch whose matcher is the item id; the tracker raises the insight and the server the push.
    func setPriceTracking(_ on: Bool, item: PriceItem) async {
        let existing = watches.first { $0.kind == .price && $0.matcher == item.id && $0.status.isOpen }
        if on, existing == nil { await addWatch(Watch(kind: .price, merchant: item.name, matcher: item.id)) }
        else if !on, let existing { await removeWatch(existing) }
    }

    // MARK: push

    /// Re-reads iOS's answer; an authorized phone re-registers every launch so the token stays current.
    func refreshPushStatus() async {
        pushStatus = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
        if pushStatus == .authorized || pushStatus == .provisional { UIApplication.shared.registerForRemoteNotifications(); await scheduleLocal() }
    }

    /// "Turn on": the system prompt, then registration. Asked once, in our words, before iOS asks in its own.
    func enablePush() async {
        askedForPush = true; UserDefaults.standard.set(true, forKey: "askedForPush")
        _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
        await refreshPushStatus()
    }

    func declinePush() { askedForPush = true; UserDefaults.standard.set(true, forKey: "askedForPush") }

    func registerDevice(token: String) async {
        #if DEBUG
        let env = "sandbox"
        #else
        let env = "production"
        #endif
        do { try await repository.register(deviceToken: token, env: env); log.info("push token registered (\(env, privacy: .public))") } catch { report(error) }
    }

    /// A push landed while the app is open: the rows it's about are already on the server.
    func pushArrived() { log.info("push arrived while open"); Task { await reload() } }

    /// A push was tapped: go where a Leaks row would.
    func handlePush(_ hints: [String: String]) {
        if let id = hints["insight"], let ins = insights.first(where: { $0.id == id }) { open(ins); return }
        if let id = hints["transaction"], let t = transactions.first(where: { $0.id == id }) { selectedTransaction = t; return }
        if let id = hints["stream"], let s = streams.first(where: { $0.id == id }) { selectedStream = s; return }
        if let id = hints["item"] { if priceItem(id: id) != nil { selectedPriceItem = .init(id: id) } else { showPricesList() }; return }
        if hints["review"] != nil { showReview = true; return }
        // Matched on the case name as well as the label, so a notification already sitting on a phone — which says
        // "next14" — still opens the right tab now that the label has changed.
        if let tab = hints["tab"], let t = Tab.allCases.first(where: {
            $0.rawValue.lowercased().replacingOccurrences(of: " ", with: "") == tab || "\($0)" == tab
        }) { self.tab = t }
    }

    /// The phone's own heads-ups, rebuilt after every recompute.
    private func scheduleLocal() async {
        let crunch = verdict?.ahead.crunch.map { (date: $0.date, shortfall: $0.shortfall) }
        let watched = Set(watches.filter { $0.kind == .merchant && $0.status.isOpen }.map(\.matcher))
        await LocalNotifications.schedule(streams: streams, watched: watched, crunch: crunch, weeklyReview: settings.notifyWeekly, headsUp: settings.notifyHeadsUp)
    }

    // MARK: since you last looked

    /// Called when the app leaves the foreground: everything after this moment is "new" next time.
    func markLooked() {
        UserDefaults.standard.set(Date.now, forKey: "lastLooked")
        UserDefaults.standard.set(transactions.filter(\.pending).map(\.id), forKey: "pendingAtLastLook")
        since = nil
    }

    private func refreshSince() {
        guard let last = UserDefaults.standard.object(forKey: "lastLooked") as? Date, !hasSeenSince(last) else { since = nil; return }
        let pendingThen = Set(UserDefaults.standard.stringArray(forKey: "pendingAtLastLook") ?? [])
        var s = Since(lastLooked: last)
        s.new = transactions.filter { ($0.createdAt ?? .distantPast) > last }.sorted { $0.displayDate > $1.displayDate }
        s.posted = transactions.filter { pendingThen.contains($0.id) && !$0.pending }
        s.payments = s.new.filter { $0.kind == .ccPayment && $0.amount > 0 }
        s.refunds = s.new.filter { $0.kind == .refund }
        since = s.isEmpty ? nil : s
    }

    private func hasSeenSince(_ last: Date) -> Bool { (UserDefaults.standard.object(forKey: "sinceSeenFor") as? Date) == last }

    /// The strip was tapped (or the sheet closed): don't show this delta again.
    func dismissSince() {
        if let s = since { UserDefaults.standard.set(s.lastLooked, forKey: "sinceSeenFor") }
        since = nil
    }

    /// A card statement inside the next two weeks that outweighs every other single outflow there.
    private func statementInsights(now: Date) -> [Insight] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: now)
        guard let end = cal.date(byAdding: .day, value: 13, to: today) else { return [] }
        let largestOther = cashflow.flatMap(\.lines).filter { $0.amount < 0 && !$0.name.hasSuffix(" statement") }.map { -$0.amount }.max() ?? 0
        return accounts.compactMap { a -> Insight? in
            guard let next = a.nextDue(now: now), next.date > today, next.date <= end,
                  let amount = a.statementPayment(default: settings.newCardsPay), amount >= largestOther else { return nil }
            let due = next.date
            let after = cashflow.first { cal.isDate($0.date, inSameDayAs: due) }?.balanceAfter
            let day = due.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
            let body: String
            if let after, after >= 0 { body = "\((a.pays ?? settings.newCardsPay).title) leaves you \(after.money) ahead through payday — still fine, but it’s the biggest thing in these two weeks." }
            else if let after { body = "It leaves checking \((-after).money) short that day. Move that much across first, or pay the minimum." }
            else { body = "The biggest thing in these two weeks." }
            return Insight(id: "statement-\(a.id)-\(Repository.day.string(from: due))", kind: .statement, tone: (after ?? 0) < 0 ? .heads : .neutral,
                           title: "\(a.name) statement lands \(day) · \(amount.money2)", body: body, rank: 4)
        }
    }

    /// The widgets read a small file in the app group; every recompute rewrites it and asks WidgetKit to redraw.
    private func publishWidgetSnapshot() {
        let snapshot: WidgetSnapshot
        if let v = verdict {
            let status: WidgetSnapshot.Status = switch v.status { case .goodShape: .good; case .onTrack: .track; case .headsUp: .heads }
            let label = switch v.status { case .goodShape: "IN GOOD SHAPE"; case .onTrack: "ON TRACK"; case .headsUp: "HEADS UP" }
            let sub = v.ahead.crunch.map { "short on \($0.date.formatted(.dateTime.weekday(.abbreviated)))" } ?? "ahead through \(v.ahead.through.formatted(.dateTime.weekday(.abbreviated)))"
            let latest = transactions.filter { !$0.excluded && ($0.kind == .spend || $0.kind == .untracked) }.prefix(3)
                .map { WidgetSnapshot.Row(id: $0.id, name: $0.displayMerchant, amount: $0.amount.money2, pending: $0.pending) }
            snapshot = WidgetSnapshot(status: status, statusLabel: label, ahead: v.ahead.amount.money, aheadSub: sub,
                                      kept: v.kept.onPacePercent.percent, keptGood: v.kept.onPacePercent >= (settings.keptTarget ?? 0.2), latest: latest, updatedAt: .now)
        } else {
            snapshot = .empty
        }
        guard snapshot != WidgetSnapshot.load() else { return }
        snapshot.save()
        WidgetCenter.shared.reloadAllTimelines()
    }

    func acknowledge(_ insight: Insight) {
        acknowledged.insert(insight.id)
        UserDefaults.standard.set(Array(acknowledged), forKey: "acknowledgedInsights")
        if insight.kind == .duplicate, let key = duplicateMerchantKey(insight) { recordDuplicateStrike(key) }
        recompute()
    }

    // MARK: "charged twice?" — asked less the more often the answer is "both are real"

    /// How many times the user has said "both are real" for a merchant; the second time, Poise stops asking there.
    private var duplicateStrikes: [String: Int] {
        get { UserDefaults.standard.dictionary(forKey: "duplicateStrikes") as? [String: Int] ?? [:] }
        set { UserDefaults.standard.set(newValue, forKey: "duplicateStrikes") }
    }
    static let duplicateStrikesToMute = 2

    func duplicateMerchantKey(_ insight: Insight) -> String? {
        guard insight.kind == .duplicate else { return nil }
        let id = String(insight.id.dropFirst("dup-".count))
        return transactions.first { $0.id == id }?.merchantKey
    }

    /// Strikes so far for the merchant behind a duplicate insight (0 when never answered).
    func duplicateStrikes(for insight: Insight) -> Int { duplicateMerchantKey(insight).map { duplicateStrikes[$0] ?? 0 } ?? 0 }

    private func recordDuplicateStrike(_ key: String) {
        var strikes = duplicateStrikes
        strikes[key, default: 0] += 1
        duplicateStrikes = strikes
        if strikes[key, default: 0] >= Self.duplicateStrikesToMute, !settings.dupMuted.contains(key) {
            Task { await setDuplicateFlagging(false, merchantKey: key) }
        }
    }

    func flagsDuplicates(merchantKey: String) -> Bool { !settings.dupMuted.contains(merchantKey) }

    /// The merchant page's "Flag double charges" switch. Off also clears the strike count, so turning it back on starts fresh.
    func setDuplicateFlagging(_ on: Bool, merchantKey: String) async {
        var s = settings
        if on { s.dupMuted.removeAll { $0 == merchantKey }; var strikes = duplicateStrikes; strikes[merchantKey] = nil; duplicateStrikes = strikes }
        else if !s.dupMuted.contains(merchantKey) { s.dupMuted.append(merchantKey) }
        await save(s)
    }

    // MARK: derived state

    /// Logos come per row from Plaid; Wallet rows carry none. When a merchant has one anywhere, every row of it gets it.
    private func fillLogos() {
        var byKey: [String: String] = [:]
        for t in raw.sorted(by: { $0.displayDate > $1.displayDate }) where t.logoURL != nil && byKey[t.merchantKey] == nil { byKey[t.merchantKey] = t.logoURL }
        logos = byKey
        guard !byKey.isEmpty else { return }
        for i in raw.indices where raw[i].logoURL == nil { if let url = byKey[raw[i].merchantKey] { raw[i].logoURL = url } }
    }

    func recompute() {
        fillLogos()
        guard hasLinkedBank else { verdict = nil; pace = nil; cashflow = []; insights = []; reviewCards = []; transactions = []; feed = []; streams = []; allStreams = []; endedStreams = []; priceItems = []; publishWidgetSnapshot(); return }
        let now = Date.now
        // A charge belongs to the day it was bought. The merchant's own order date beats the card's, which is the day
        // it shipped — or, on Apple Card, only the day it posted.
        var all = raw
        for i in all.indices {
            guard let ref = all[i].orderRef, let placed = orderItems[ref]?.placed else { continue }
            all[i].purchasedDate = placed
        }
        all = TransferDetector.pair(all, accounts: accounts)
        all = RefundMatcher.match(all)
        transactions = all
        feed = TransferDetector.collapsed(all)
        // Cards whose provider gives a due date but no statement balance (Apple Card) get one rebuilt from their rows.
        for i in accounts.indices where accounts[i].role == .credit && (accounts[i].statementAmount == nil || accounts[i].statementIsEstimate) {
            accounts[i].statementAmount = StatementEstimator.statement(for: accounts[i], transactions: all)
            accounts[i].statementIsEstimate = accounts[i].statementAmount != nil
        }
        let rows = all.filter { !$0.excluded }                       // "leave it out": in the feed, out of every number
        allStreams = RecurringDetector.detect(rows, now: now, categories: categories).map { s in
            var s = s
            if let k = settings.streamKinds[s.id].flatMap(StreamKind.init(rawValue:)), s.kind != .income { s.kind = k }   // re-filed by hand
            return s
        }
        let dismissed = Set(settings.dismissedStreams)
        streams = allStreams.filter { !dismissed.contains($0.id) && !$0.isEnded && settings.cancelledStreams[$0.id] == nil }
        endedStreams = allStreams.filter { !dismissed.contains($0.id) && $0.kind != .income && ($0.isEnded || settings.cancelledStreams[$0.id] != nil) }
            .sorted { (settings.cancelledStreams[$0.id] ?? $0.endedAt ?? .distantPast) > (settings.cancelledStreams[$1.id] ?? $1.endedAt ?? .distantPast) }
        let before = watches
        watches = WatchEngine.evaluate(watches, transactions: all, now: now)
        persistWatchChanges(from: before)
        refreshSince()
        let input = VerdictInput(accounts: accounts, transactions: rows, streams: streams, now: now, nextPayday: settings.paydayOverride,
                                 keptTarget: settings.keptTarget ?? 0.2, committedSavings: settings.committedSavings, categories: categories, newCardsPay: settings.newCardsPay)
        let v = VerdictEngine.verdict(for: input)
        let p = PaceEngine.pace(transactions: rows, streams: streams, now: now, categories: categories)
        cashflow = CashflowEngine.nextDays(horizonDays, accounts: accounts, streams: streams, transactions: rows, now: now, newCardsPay: settings.newCardsPay)
        let ranked = InsightEngine.rank(.init(verdict: v, pace: p, streams: streams, transactions: rows, now: now, acknowledged: acknowledged, dupMuted: Set(settings.dupMuted)))
        let tracked = Set(watches.filter { $0.kind == .price && $0.status.isOpen }.map(\.matcher))
        priceItems = PriceTracker.items(in: all, streams: allStreams.filter { !dismissed.contains($0.id) && isPlanLike($0) }, now: now).map { var i = $0; i.tracked = tracked.contains(i.id); return i }
        let overspent = settings.watchedCategories.compactMap { id -> Insight? in
            guard let h = CategoryHistoryEngine.history(categoryID: id, transactions: all, now: now, categories: categories) else { return nil }
            return CategoryHistoryEngine.overspendInsight(categoryID: id, name: categories.resolve(id).name, history: h, now: now)
        }
        let leakInsights = Cancellations.chargedAfterCancel(streams: allStreams, cancelled: settings.cancelledStreams, transactions: rows) + Cancellations.returned(streams: streams, now: now) + overspent
        let watchInsights = (leakInsights + WatchEngine.insights(watches, transactions: rows, now: now) + statementInsights(now: now) + PriceTracker.insights(priceItems, now: now)).filter { !acknowledged.contains($0.id) }
        insights = (ranked + watchInsights).sorted { $0.rank < $1.rank }
        fees = Anomalies.feesYearToDate(rows, now: now)
        reviewCards = WeeklyReview.cards(transactions: rows, streams: streams, insights: insights, cashflow: cashflow, verdict: v, now: now, categories: categories)
        if pushStatus == .authorized || pushStatus == .provisional { Task { await scheduleLocal() } }
        // Anomalies count toward the status rule, so the verdict is finalized after ranking.
        let anomalies = insights.filter { [.duplicate, .fee, .priceUp, .watchTriggered, .refundOverdue, .priceMoved, .cancelledCharge].contains($0.kind) }.count
        verdict = Verdict(status: VerdictEngine.status(ahead: v.ahead, kept: v.kept, target: input.keptTarget, anomalies: anomalies), ahead: v.ahead, kept: v.kept)
        publishWidgetSnapshot()
        pace = p
    }
}
