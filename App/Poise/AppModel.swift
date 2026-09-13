import Foundation
import Observation
import PoiseKit

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

    var hasLinkedBank: Bool { !accounts.isEmpty }

    func start() async {
        // Bank linking arrives with M2. Until then the app boots to the empty verdict.
        recompute()
    }

    func recompute() {
        guard hasLinkedBank else { verdict = nil; return }
        let input = VerdictInput(accounts: accounts, transactions: transactions, streams: streams, now: .now)
        verdict = VerdictEngine.verdict(for: input)
    }
}
