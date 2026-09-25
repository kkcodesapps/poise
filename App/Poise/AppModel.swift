import Foundation
import AuthenticationServices
import Observation
import OSLog
import Supabase
import PoiseKit

private let log = Logger(subsystem: "com.koliokolev.poise", category: "app")

/// The only UI state. Views read from here; services write here. Everything derived is recomputed in one place.
@MainActor @Observable
final class AppModel {
    enum Tab: String, CaseIterable, Identifiable {
        case home = "Home", leaks = "Leaks", pace = "Pace", next14 = "Next 14", whereTab = "Where"
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
    var whereAnchor: Date = .now
    var whereWindow: DateInterval = Periods.window(.month, containing: .now)
    var showWatching = false
    var profilePath: [String] = []
    var lastSync: Date?
    var institutions: [String] = []
    var relinkNeeded: [Repository.Item] = []
    /// Apple Card / Apple Cash / Savings are read from Wallet on this phone; true once the server has that item.
    var walletLinked = false
    /// Wallet access was turned off in Settings after linking; the banner sends the user back there.
    var walletAccessLost = false
    var showLinkOptions = false
    private var lastForegroundRefresh: Date?
    var isLoading = false
    var isLinking = false
    var errorMessage: String?
    var selectedTransaction: PoiseKit.Transaction?
    var selectedStream: RecurringStream?
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
    var openWatches: [Watch] { watches.filter { $0.status.isOpen } }
    var owedBack: Decimal { openWatches.filter { $0.kind == .refund }.reduce(0) { $0 + ($1.expectedAmount ?? 0) } }
    func watch(for transactionID: String) -> Watch? { watches.first { $0.transactionID == transactionID && $0.status.isOpen } }
    func isWatched(merchantKey: String) -> Bool { watches.contains { $0.kind == .merchant && $0.matcher == merchantKey && $0.status.isOpen } }

    /// Errors worth an alert. A cancelled request — the pull ended, the view went away, the app backgrounded — isn't one.
    private func report(_ error: Error) {
        if error is CancellationError || (error as? URLError)?.code == .cancelled { return }
        report(error)
    }

    /// Where: the current window's breakdown, recomputed on demand.
    var breakdown: Breakdown? {
        guard hasLinkedBank else { return nil }
        return CategoryBreakdown.compute(transactions: transactions, period: wherePeriod, window: whereWindow, now: .now, categories: categories)
    }
    var whereIsCurrent: Bool { whereWindow.contains(.now) }
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
            let loaded = await reload()
            if !loaded, !hasLinkedBank { errorMessage = nil; launch = .failed; return }   // nothing to show behind the splash
            let elapsed = Date.now.timeIntervalSince(began)
            if elapsed < 0.5 { try? await Task.sleep(for: .seconds(0.5 - elapsed)) }
            launch = .ready
            if settings.faceID { isLocked = true; await unlock() }
            if walletLinked { Task { if await syncWallet() { await reload() } } }
            #if DEBUG
            // `-tab leaks|pace|next14` and `-review` open a screen on launch (screenshots, UI tests).
            let args = ProcessInfo.processInfo.arguments
            if let i = args.firstIndex(of: "-tab"), i + 1 < args.count { tab = Tab.allCases.first { $0.rawValue.lowercased().replacingOccurrences(of: " ", with: "") == args[i + 1].lowercased() } ?? .home }
            if args.contains("-review") { showReview = true }
            if args.contains("-profile") { showProfile = true }
            if args.contains("-categories") { showProfile = true; profilePath = ["categories"] }
            if args.contains("-watching") { showProfile = true; profilePath = ["watching"] }
            // `-account` / `-hidden` open the first account's page / the hidden list; `-hide-first` hides the first account first.
            if args.contains("-hide-first"), let a = accounts.first { await setHidden(true, for: a); showProfile = true; profilePath = ["account:\(a.id)"] }
            else if args.contains("-account"), let a = allAccounts.first { showProfile = true; profilePath = ["account:\(a.id)"] }
            if args.contains("-hidden") { showProfile = true; profilePath = ["hidden"] }
            // `-open-insight dup|fee|price` opens the first insight of that kind the way a Leaks row would; `-open-stream` the first subscription.
            if let i = args.firstIndex(of: "-open-insight"), i + 1 < args.count {
                let kind: Insight.Kind? = ["dup": .duplicate, "fee": .fee, "price": .priceUp][args[i + 1]]
                if let ins = insights.first(where: { $0.kind == kind }) { Task { try? await Task.sleep(for: .seconds(1)); open(ins) } }   // after the splash fade
            }
            if args.contains("-open-stream"), let s = streams.first(where: { $0.kind == .subscription }) { selectedStream = s }
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
            accounts = s.accounts
            hiddenAccounts = s.hiddenAccounts
            raw = s.transactions
            lastSync = s.lastSync
            institutions = s.institutions
            relinkNeeded = s.relinkNeeded
            walletLinked = s.walletLinked
            settings = p
            customCategories = s.customCategories
            watches = s.watches
            rebuildCategories()
            recompute()
            if hasLinkedBank, !rememberedLinked { rememberedLinked = true; UserDefaults.standard.set(true, forKey: "hasLinkedBefore") }
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
            if try await withDeadline(120, { try await wallet.connect() }) { walletLinked = true; walletAccessLost = false; await reload() }
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

    /// Opens Plaid Link; on success the server has already run the first sync, so a reload shows real rows.
    func link() async {
        guard !isLinking else { return }
        isLinking = true; defer { isLinking = false }
        do {
            let linker = self.linker ?? BankLinker(client: Backend.client)
            self.linker = linker
            if try await linker.link() != nil { await reload() }
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
            if try await linker.link(relink: item.id) != nil { await refresh(trigger: "relink") }
        } catch { report(error) }
    }

    func readSession() async {
        let session = try? await Backend.client.auth.session
        isAnonymous = session?.user.isAnonymous ?? true
        accountName = (session?.user.userMetadata["full_name"]?.stringValue).flatMap { $0.isEmpty ? nil : $0 } ?? session?.user.email
    }

    // MARK: account

    func signInWithApple(_ credential: ASAuthorizationAppleIDCredential, nonce: String) async {
        do {
            try await Auth.signIn(with: credential, nonce: nonce, client: Backend.client)
            await readSession()
            await reload()
        } catch { report(error) }
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
        accounts = []; hiddenAccounts = []; raw = []; transactions = []; streams = []; verdict = nil; pace = nil; cashflow = []; insights = []; reviewCards = []
        lastSync = nil; institutions = []; relinkNeeded = []; walletLinked = false; walletAccessLost = false; settings = Repository.Settings(); isAnonymous = true; accountName = nil
        customCategories = []; watches = []; categories = .builtIn
        rememberedLinked = false; UserDefaults.standard.removeObject(forKey: "hasLinkedBefore")
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
        if settings.faceID, !isLocked { isLocked = true; await unlock() }
        guard hasLinkedBank else { return }
        if let last = lastForegroundRefresh, Date.now.timeIntervalSince(last) < 15 * 60 { await reload(); return }
        lastForegroundRefresh = .now
        await refresh(trigger: "foreground")
    }

    /// Foreground / pull-to-refresh: fresh balances now; new bank transactions arrive by webhook and a later reload.
    /// Wallet has no webhook, so its changes are read and sent right here.
    func refresh(trigger: String = "pull") async {
        async let banks: Void = refreshBanks(trigger: trigger)
        async let walletChanged = syncWallet()
        _ = await (banks, walletChanged)
        await reload()
    }

    private func refreshBanks(trigger: String) async {
        struct Body: Encodable { let trigger: String }
        _ = try? await Backend.client.functions.invoke("refresh", options: FunctionInvokeOptions(body: Body(trigger: trigger)))
    }

    // MARK: corrections

    func correct(_ t: PoiseKit.Transaction, kind: TransactionKind, categoryID: String?, always: Bool) async {
        guard let i = raw.firstIndex(where: { $0.id == t.id }) else { return }
        raw[i].kind = kind; raw[i].categoryID = categoryID; raw[i].pairID = nil
        var ids = [t.id]
        if always {
            for j in raw.indices where raw[j].merchantKey == t.merchantKey && raw[j].id != t.id && raw[j].kind != .income {
                raw[j].kind = kind; raw[j].categoryID = categoryID; raw[j].pairID = nil; ids.append(raw[j].id)
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

    func addWatch(_ w: Watch) async {
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
        case .watchTriggered, .refundOverdue, .refundArrived: tab = .home; showWatching = true
        case .crunch: tab = .next14
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
        return transactions.filter { "\($0.kind.rawValue)|\($0.merchantKey)" == s.id && $0.displayDate >= since }.sorted { $0.displayDate > $1.displayDate }
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

    func acknowledge(_ insight: Insight) {
        acknowledged.insert(insight.id)
        UserDefaults.standard.set(Array(acknowledged), forKey: "acknowledgedInsights")
        recompute()
    }

    // MARK: derived state

    func recompute() {
        guard hasLinkedBank else { verdict = nil; pace = nil; cashflow = []; insights = []; reviewCards = []; transactions = []; streams = []; return }
        let now = Date.now
        var rows = TransferDetector.pair(raw, accounts: accounts)
        rows = RefundMatcher.match(rows)
        transactions = rows
        streams = RecurringDetector.detect(rows, now: now, categories: categories).filter { !settings.dismissedStreams.contains($0.id) }
        let before = watches
        watches = WatchEngine.evaluate(watches, transactions: rows, now: now)
        persistWatchChanges(from: before)
        let input = VerdictInput(accounts: accounts, transactions: rows, streams: streams, now: now, nextPayday: settings.paydayOverride,
                                 keptTarget: settings.keptTarget ?? 0.2, committedSavings: settings.committedSavings, categories: categories)
        let v = VerdictEngine.verdict(for: input)
        let p = PaceEngine.pace(transactions: rows, streams: streams, now: now, categories: categories)
        cashflow = CashflowEngine.nextDays(accounts: accounts, streams: streams, transactions: rows, now: now)
        let ranked = InsightEngine.rank(.init(verdict: v, pace: p, streams: streams, transactions: rows, now: now, acknowledged: acknowledged))
        let watchInsights = WatchEngine.insights(watches, transactions: rows, now: now).filter { !acknowledged.contains($0.id) }
        insights = (ranked + watchInsights).sorted { $0.rank < $1.rank }
        fees = Anomalies.feesYearToDate(rows, now: now)
        reviewCards = WeeklyReview.cards(transactions: rows, streams: streams, insights: insights, cashflow: cashflow, verdict: v, now: now, categories: categories)
        // Anomalies count toward the status rule, so the verdict is finalized after ranking.
        let anomalies = insights.filter { [.duplicate, .fee, .priceUp, .watchTriggered, .refundOverdue].contains($0.kind) }.count
        verdict = Verdict(status: VerdictEngine.status(ahead: v.ahead, kept: v.kept, target: input.keptTarget, anomalies: anomalies), ahead: v.ahead, kept: v.kept)
        pace = p
    }
}
