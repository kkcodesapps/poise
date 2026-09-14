import Foundation
import Observation
import OSLog
import Supabase
import PoiseKit

private let log = Logger(subsystem: "com.koliokolev.poise", category: "app")

/// The only UI state. Views read from here; services write here.
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
    var transactions: [Transaction] = []
    var streams: [RecurringStream] = []
    var verdict: Verdict?
    var lastSync: Date?
    var isLoading = false
    var isLinking = false
    var errorMessage: String?

    private let repository = Repository(client: Backend.client)
    private var linker: BankLinker?

    var hasLinkedBank: Bool { !accounts.isEmpty }

    func start() async {
        do {
            try await Backend.ensureSession()
            log.info("session ok")
            await reload()
            log.info("loaded: \(self.accounts.count) accounts, \(self.transactions.count) transactions")
            #if DEBUG
            // `-sandbox-link` on the launch arguments links Plaid's test bank without the Link UI (sandbox only).
            let wantsSandbox = ProcessInfo.processInfo.arguments.contains("-sandbox-link")
            log.info("sandbox flag: \(wantsSandbox), linked: \(self.hasLinkedBank)")
            if !hasLinkedBank, wantsSandbox {
                try await Backend.client.functions.invoke("sandbox-link")
                log.info("sandbox-link done")
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
            let snap = try await repository.load()
            accounts = snap.accounts
            transactions = TransferDetector.pair(snap.transactions, accounts: snap.accounts)
            streams = snap.streams
            lastSync = snap.lastSync
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

    func recompute() {
        guard hasLinkedBank else { verdict = nil; return }
        let input = VerdictInput(accounts: accounts, transactions: transactions, streams: streams, now: .now)
        verdict = VerdictEngine.verdict(for: input)
    }
}
