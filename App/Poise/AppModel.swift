import Foundation
import Observation
import OSLog
import Supabase
import PoiseKit

private let log = Logger(subsystem: "com.koliokolev.poise", category: "app")

/// The only UI state. Views read from here; services write here. Everything derived is recomputed in one place.
@MainActor @Observable
final class AppModel {
    enum Tab: String, CaseIterable, Identifiable {
        case home = "Home", leaks = "Leaks", pace = "Pace", next14 = "Next 14"
        var id: String { rawValue }
        var symbol: String {
            switch self {
            case .home: "house"
            case .leaks: "drop"
            case .pace: "chart.line.uptrend.xyaxis"
            case .next14: "calendar"
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
    var lastSync: Date?
    var institutions: [String] = []
    var isLoading = false
    var isLinking = false
    var errorMessage: String?
    var selectedTransaction: PoiseKit.Transaction?
    var showProfile = false
    var showReview = false

    private let repository = Repository(client: Backend.client)
    private var linker: BankLinker?
    private var raw: [PoiseKit.Transaction] = []
    private(set) var acknowledged: Set<String> = Set(UserDefaults.standard.stringArray(forKey: "acknowledgedInsights") ?? [])

    var hasLinkedBank: Bool { !accounts.isEmpty }
    var topInsight: Insight? { insights.first }
    var isReviewDay: Bool { Calendar.current.component(.weekday, from: .now) == 1 }

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

    func reload() async {
        isLoading = true; defer { isLoading = false }
        do {
            async let snap = repository.load()
            async let prefs = repository.loadSettings()
            let (s, p) = try await (snap, prefs)
            accounts = s.accounts
            raw = s.transactions
            lastSync = s.lastSync
            institutions = s.institutions
            settings = p
            recompute()
        } catch {
            log.error("reload failed: \(error.localizedDescription, privacy: .public)")
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

    /// Foreground / pull-to-refresh: fresh balances now; new transactions arrive by webhook and a later reload.
    func refresh(trigger: String = "pull") async {
        struct Body: Encodable { let trigger: String }
        _ = try? await Backend.client.functions.invoke("refresh", options: FunctionInvokeOptions(body: Body(trigger: trigger)))
        await reload()
    }

    // MARK: corrections

    func correct(_ t: PoiseKit.Transaction, kind: TransactionKind, category: SpendCategory?, always: Bool) async {
        guard let i = raw.firstIndex(where: { $0.id == t.id }) else { return }
        raw[i].kind = kind; raw[i].category = category; raw[i].pairID = nil
        var ids = [t.id]
        if always {
            for j in raw.indices where raw[j].merchantKey == t.merchantKey && raw[j].id != t.id && raw[j].kind != .income {
                raw[j].kind = kind; raw[j].category = category; raw[j].pairID = nil; ids.append(raw[j].id)
            }
        }
        recompute()
        do {
            if always { try await repository.upsertRule(merchant: t.merchant, kind: kind, category: category, applyTo: ids) }
            else { try await repository.update(transactionID: t.id, kind: kind, category: category) }
        } catch { errorMessage = error.localizedDescription }
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
        streams = RecurringDetector.detect(rows, now: now)
        let input = VerdictInput(accounts: accounts, transactions: rows, streams: streams, now: now, nextPayday: settings.paydayOverride,
                                 keptTarget: settings.keptTarget ?? 0.2, committedSavings: settings.committedSavings)
        let v = VerdictEngine.verdict(for: input)
        let p = PaceEngine.pace(transactions: rows, streams: streams, now: now)
        cashflow = CashflowEngine.nextDays(accounts: accounts, streams: streams, transactions: rows, now: now)
        insights = InsightEngine.rank(.init(verdict: v, pace: p, streams: streams, transactions: rows, now: now, acknowledged: acknowledged))
        fees = Anomalies.feesYearToDate(rows, now: now)
        reviewCards = WeeklyReview.cards(transactions: rows, streams: streams, insights: insights, cashflow: cashflow, verdict: v, now: now)
        // Anomalies count toward the status rule, so the verdict is finalized after ranking.
        let anomalies = insights.filter { [.duplicate, .fee, .priceUp].contains($0.kind) }.count
        verdict = Verdict(status: VerdictEngine.status(ahead: v.ahead, kept: v.kept, target: input.keptTarget, anomalies: anomalies), ahead: v.ahead, kept: v.kept)
        pace = p
    }
}
