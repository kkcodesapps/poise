import Foundation

/// One day of the next fourteen: what's expected to leave or land, and the spending balance after it.
public struct CashflowDay: Hashable, Sendable, Identifiable {
    public struct Line: Hashable, Sendable { public let name: String; public let amount: Decimal; public init(name: String, amount: Decimal) { self.name = name; self.amount = amount } }   // signed
    public let date: Date
    public let lines: [Line]
    public let balanceAfter: Decimal
    public let isToday: Bool
    public var isCrunch: Bool { balanceAfter < 0 }
    public var hasIncome: Bool { lines.contains { $0.amount > 0 } }
    public var id: Date { date }
}

public enum CashflowEngine {
    public static func nextDays(_ count: Int = 14, accounts: [Account], streams: [RecurringStream], transactions: [Transaction], now: Date, calendar: Calendar = .current) -> [CashflowDay] {
        let today = calendar.startOfDay(for: now)
        var balance = accounts.filter { $0.role == .spending }.reduce(Decimal(0)) { $0 + $1.balance }
        let end = calendar.date(byAdding: .day, value: count - 1, to: today)!
        var byDay: [Date: [CashflowDay.Line]] = [:]
        for s in streams {
            for d in s.occurrences(after: today.addingTimeInterval(-1), through: end, calendar: calendar) {
                let day = calendar.startOfDay(for: d)
                if day == today { continue }   // today's known charges are already in the feed / balance
                byDay[day, default: []].append(.init(name: s.merchant, amount: s.kind == .income ? s.amount : -s.amount))
            }
        }
        // Today shows what's pending (already reflected in available balance, so not subtracted again).
        let pendingToday = transactions.filter { $0.pending && calendar.isDate($0.displayDate, inSameDayAs: today) }
            .map { CashflowDay.Line(name: $0.merchant + " (pending)", amount: $0.amount) }
        var out: [CashflowDay] = []
        var day = today
        while day <= end {
            let lines = day == today ? pendingToday : (byDay[day] ?? [])
            if day != today { balance += lines.reduce(0) { $0 + $1.amount } }
            out.append(CashflowDay(date: day, lines: lines, balanceAfter: balance, isToday: day == today))
            day = calendar.date(byAdding: .day, value: 1, to: day)!
        }
        return out
    }
}
