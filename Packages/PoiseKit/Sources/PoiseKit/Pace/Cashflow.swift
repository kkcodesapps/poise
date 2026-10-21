import Foundation

/// One day of the next fourteen: what's expected to leave or land, and the spending balance after it.
public struct CashflowDay: Hashable, Sendable, Identifiable {
    /// Signed. `viaCard` names the card when the charge settles through its statement rather than leaving checking that day.
    public struct Line: Hashable, Sendable {
        public let name: String; public let amount: Decimal; public let viaCard: String?
        public init(name: String, amount: Decimal, viaCard: String? = nil) { self.name = name; self.amount = amount; self.viaCard = viaCard }
        public var movesCash: Bool { viaCard == nil }
    }
    public let date: Date
    public let lines: [Line]
    public let balanceAfter: Decimal
    public let isToday: Bool
    public var isCrunch: Bool { balanceAfter < 0 }
    public var hasIncome: Bool { lines.contains { $0.amount > 0 && $0.movesCash } }
    /// What actually leaves or lands in checking that day.
    public var cashMoved: Decimal { lines.filter(\.movesCash).reduce(0) { $0 + $1.amount } }
    public var id: Date { date }
}

public enum CashflowEngine {
    public static func nextDays(_ count: Int = 14, accounts: [Account], streams: [RecurringStream], transactions: [Transaction], now: Date, calendar: Calendar = .current, paysCardsInFull: Bool = true) -> [CashflowDay] {
        let today = calendar.startOfDay(for: now)
        var balance = accounts.filter { $0.role == .spending }.reduce(Decimal(0)) { $0 + $1.balance }
        let end = calendar.date(byAdding: .day, value: count - 1, to: today)!
        var byDay: [Date: [CashflowDay.Line]] = [:]
        // Card statements leave checking on their due date. Card payments never form streams, so nothing is counted twice.
        for a in accounts where !a.hidden {
            guard let due = a.statementDue, let amount = a.statementPayment(paysInFull: paysCardsInFull) else { continue }
            let day = calendar.startOfDay(for: due)
            if day > today, day <= end { byDay[day, default: []].append(.init(name: "\(a.name) statement", amount: -amount)) }
        }
        let cards = Dictionary(uniqueKeysWithValues: accounts.filter { $0.role == .credit }.map { ($0.id, $0.name) })
        for s in streams {
            // A subscription on a card is worth seeing, but it's the statement that leaves checking.
            let via = s.accountID.flatMap { cards[$0] }
            for d in s.occurrences(after: today.addingTimeInterval(-1), through: end, calendar: calendar) {
                let day = calendar.startOfDay(for: d)
                if day == today { continue }   // today's known charges are already in the feed / balance
                byDay[day, default: []].append(.init(name: s.merchant, amount: s.kind == .income ? s.amount : -s.amount, viaCard: via))
            }
        }
        // Today shows what's pending (already reflected in available balance, so not subtracted again). A card payment
        // is money leaving whatever it was paid from, never income — some banks sign it positive on the card — and the
        // pair is one movement, so only the side that actually moves cash is listed.
        let creditIDs = Set(accounts.filter { $0.role == .credit }.map(\.id))
        let todaysPending = transactions.filter { $0.pending && calendar.isDate($0.displayDate, inSameDayAs: today) }
        let cashSides = todaysPending.filter { $0.kind == .ccPayment && !creditIDs.contains($0.accountID) }
        let cashPairs = Set(cashSides.compactMap(\.pairID)), cashAmounts = Set(cashSides.map(\.magnitude))
        let pendingToday = todaysPending
            // The card's copy of a payment that also left a spending account — same pair, or the same amount the same day.
            .filter { !($0.kind == .ccPayment && creditIDs.contains($0.accountID) && ($0.pairID.map(cashPairs.contains) == true || cashAmounts.contains($0.magnitude))) }
            .map { CashflowDay.Line(name: $0.merchant + " (pending)", amount: $0.kind == .ccPayment ? -$0.magnitude : $0.amount) }
        var out: [CashflowDay] = []
        var day = today
        while day <= end {
            let lines = day == today ? pendingToday : (byDay[day] ?? [])
            if day != today { balance += lines.filter(\.movesCash).reduce(0) { $0 + $1.amount } }
            out.append(CashflowDay(date: day, lines: lines, balanceAfter: balance, isToday: day == today))
            day = calendar.date(byAdding: .day, value: 1, to: day)!
        }
        return out
    }
}
