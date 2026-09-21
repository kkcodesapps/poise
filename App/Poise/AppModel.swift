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
    private var lastForegroundRefresh: Date?
    var isLoading = false
    var isLinking = false
    var errorMessage: String?
    var selectedTransaction: PoiseKit.Transaction?
    var showProfile = false
    var showReview = false
    var isLocked = false
    var isAnonymous = true
    var accountName: String?

    private let repository = Repository(client: Backend.client)
    private var linker: BankLinker?
    private var raw: [PoiseKit.Transaction] = []
    private(set) var acknowledged: Set<String> = Set(UserDefaults.standard.stringArray(forKey: "acknowledgedInsights") ?? [])

    var hasLinkedBank: Bool { !accounts.isEmpty }
    var topInsight: Insight? { insights.first }
    var isReviewDay: Bool { Calendar.current.component(.weekday, from: .now) == 1 }
    var openWatches: [Watch] { watches.filter { $0.status.isOpen } }
    var owedBack: Decimal { openWatches.filter { $0.kind == .refund }.reduce(0) { $0 + ($1.expectedAmount ?? 0) } }
    func watch(for transactionID: String) -> Watch? { watches.first { $0.transactionID == transactionID && $0.status.isOpen } }
    func isWatched(merchantKey: String) -> Bool { watches.contains { $0.kind == .merchant && $0.matcher == merchantKey && $0.status.isOpen } }

    /// Where: the current window's breakdown, recomputed on demand.
    var breakdown: Breakdown? {
        guard hasLinkedBank else { return nil }
        return CategoryBreakdown.compute(transactions: transactions, period: wherePeriod, window: whereWindow, now: .now, categories: categories)
    }
    var whereIsCurrent: Bool { whereWindow.contains(.now) }
    func stepWhere(_ n: Int) { let w = Periods.shift(whereWindow, wherePeriod, by: n); if w.start <= .now { whereWindow = w; whereAnchor = w.start } }

    func start() async {
        do {
            try await Backend.ensureSession()
            await reload()
            #if DEBUG
            // `-tab leaks|pace|next14` and `-review` open a screen on launch (screenshots, UI tests).
            let args = ProcessInfo.processInfo.arguments
            if let i = args.firstIndex(of: "-tab"), i + 1 < args.count { tab = Tab.allCases.first { $0.rawValue.lowercased().replacingOccurrences(of: " ", with: "") == args[i + 1].lowercased() } ?? .home }
            if args.contains("-review") { showReview = true }
            if args.contains("-profile") { showProfile = true }
            if args.contains("-categories") { showProfile = true; profilePath = ["categories"] }
            if args.contains("-watching") { showProfile = true; profilePath = ["watching"] }
            // `-sandbox-link` on the launch arguments links Plaid's test bank without the Link UI (sandbox only).
            if !hasLinkedBank, ProcessInfo.processInfo.arguments.contains("-sandbox-link") {
                try await Backend.client.functions.invoke("sandbox-link")
                await reload()
            }
            #endif
        } catch {
            log.error("start failed: \(error.localizedDescription, privacy: .public)")
            errorMessage = error.localizedDescription
        }
    }

    func reload(retry: Bool = true) async {
        isLoading = true; defer { isLoading = false }
        do {
            async let snap = repository.load()
            async let prefs = repository.loadSettings()
            let (s, p) = try await (snap, prefs)
            accounts = s.accounts
            raw = s.transactions
            lastSync = s.lastSync
            institutions = s.institutions
            relinkNeeded = s.relinkNeeded
            settings = p
            customCategories = s.customCategories
            watches = s.watches
            rebuildCategories()
            recompute()
        } catch {
            log.error("reload failed: \(error.localizedDescription, privacy: .public)")
            // One quiet retry covers token-refresh clock skew ("JWT issued at future") and a dropped connection.
            if retry { try? await Task.sleep(for: .seconds(2)); await reload(retry: false); return }
            errorMessage = error.localizedDescription
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
            errorMessage = error.localizedDescription
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
        } catch { errorMessage = error.localizedDescription }
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
        } catch { errorMessage = error.localizedDescription }
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
        } catch { errorMessage = error.localizedDescription }
    }

    private func resetState() {
        accounts = []; raw = []; transactions = []; streams = []; verdict = nil; pace = nil; cashflow = []; insights = []; reviewCards = []
        lastSync = nil; institutions = []; relinkNeeded = []; settings = Repository.Settings(); isAnonymous = true; accountName = nil
        customCategories = []; watches = []; categories = .builtIn
    }

    /// Everything Poise holds about the user, as one JSON file for the share sheet.
    func exportFile() throws -> URL {
        struct Export: Encodable { let exportedAt: Date; let accounts: [Account]; let transactions: [PoiseKit.Transaction]; let streams: [RecurringStream] }
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]; encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(Export(exportedAt: .now, accounts: accounts, transactions: transactions, streams: streams))
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

    /// Foreground / pull-to-refresh: fresh balances now; new transactions arrive by webhook and a later reload.
    func refresh(trigger: String = "pull") async {
        struct Body: Encodable { let trigger: String }
        _ = try? await Backend.client.functions.invoke("refresh", options: FunctionInvokeOptions(body: Body(trigger: trigger)))
        await reload()
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
        } catch { errorMessage = error.localizedDescription }
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
        } catch { errorMessage = error.localizedDescription; return nil }
    }

    func updateCategory(_ c: PoiseKit.Category) async {
        if c.builtIn {
            var s = settings; s.categoryLens[c.id] = c.lens.rawValue; await save(s); rebuildCategories(); recompute()
        } else {
            if let i = customCategories.firstIndex(where: { $0.id == c.id }) { customCategories[i] = c }
            rebuildCategories(); recompute()
            do { try await repository.update(category: c) } catch { errorMessage = error.localizedDescription }
        }
    }

    func deleteCategory(_ c: PoiseKit.Category) async {
        guard !c.builtIn else { return }
        customCategories.removeAll { $0.id == c.id }
        for j in raw.indices where raw[j].categoryID == c.id { raw[j].categoryID = SpendCategory.other.rawValue }
        rebuildCategories(); recompute()
        do { try await repository.delete(categoryID: c.id) } catch { errorMessage = error.localizedDescription }
    }

    // MARK: watches

    func addWatch(_ w: Watch) async {
        watches.insert(w, at: 0); recompute()
        do { try await repository.insert(watch: w) } catch { errorMessage = error.localizedDescription }
    }

    func updateWatch(_ w: Watch) async {
        if let i = watches.firstIndex(where: { $0.id == w.id }) { watches[i] = w }
        recompute()
        do { try await repository.update(watch: w) } catch { errorMessage = error.localizedDescription }
    }

    func closeWatch(_ w: Watch) async { var c = w; c.status = .closed; c.resolvedAt = .now; await updateWatch(c) }

    func removeWatch(_ w: Watch) async {
        watches.removeAll { $0.id == w.id }; recompute()
        do { try await repository.delete(watchID: w.id) } catch { errorMessage = error.localizedDescription }
    }

    /// Statuses the engine changed (refund arrived, overdue, merchant charged again) are written back so the server and pushes agree.
    private func persistWatchChanges(from before: [Watch]) {
        let changed = watches.filter { w in before.first { $0.id == w.id }?.status != w.status }
        guard !changed.isEmpty else { return }
        Task { for w in changed { try? await repository.update(watch: w) } }
    }

    func setRole(_ role: AccountRole, for account: Account) async {
        guard let i = accounts.firstIndex(where: { $0.id == account.id }) else { return }
        accounts[i].role = role; recompute()
        do { try await repository.update(accountID: account.id, role: role) } catch { errorMessage = error.localizedDescription }
    }

    func save(_ s: Repository.Settings) async {
        settings = s; recompute()
        do { try await repository.save(s) } catch { errorMessage = error.localizedDescription }
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
        streams = RecurringDetector.detect(rows, now: now, categories: categories)
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
