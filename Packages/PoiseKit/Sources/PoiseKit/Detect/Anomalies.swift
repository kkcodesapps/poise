import Foundation

/// The things worth a heads-up that aren't about the budget: double charges and fees.
public enum Anomalies {
    public struct Duplicate: Hashable, Sendable { public let first: Transaction; public let second: Transaction; public init(first: Transaction, second: Transaction) { self.first = first; self.second = second } }

    /// The smallest charge worth asking about; two identical tolls or coffees are a habit, not an accident.
    public static let minimumDuplicateAmount: Decimal = 10

    /// Same merchant, same account, same amount, same day — the shape of one purchase posting twice. Leaves alone small
    /// amounts, merchants where that exact amount recurs (a weekly car wash), pairs on different cards (two purchases),
    /// and merchants the user has said not to ask about.
    public static func duplicates(in transactions: [Transaction], muted: Set<String> = [], calendar: Calendar = .current) -> [Duplicate] {
        // Two charges only — a refund that mirrors a charge is the opposite of a duplicate.
        let spend = transactions.filter { ($0.kind == .spend || $0.kind == .untracked) && $0.amount < 0 && !$0.excluded }.sorted { $0.displayDate < $1.displayDate }
        var byShape: [String: [Date]] = [:]
        for t in spend { byShape["\(t.merchantKey)|\(t.amount)", default: []].append(t.displayDate) }
        func habitual(_ t: Transaction) -> Bool {
            // Four or more of the same amount at the same place inside 90 days, counting this pair, is a pattern.
            guard let from = calendar.date(byAdding: .day, value: -90, to: t.displayDate) else { return false }
            return (byShape["\(t.merchantKey)|\(t.amount)"] ?? []).filter { $0 >= from && $0 <= t.displayDate }.count >= 4
        }
        var out: [Duplicate] = []
        var taken: Set<String> = []
        for (i, a) in spend.enumerated() where !taken.contains(a.id) {
            guard a.magnitude >= minimumDuplicateAmount, !muted.contains(a.merchantKey) else { continue }
            for b in spend[(i + 1)...] {
                if !calendar.isDate(b.displayDate, inSameDayAs: a.displayDate) { break }
                guard b.merchantKey == a.merchantKey, b.amount == a.amount, b.accountID == a.accountID, b.id != a.id, !taken.contains(b.id) else { continue }
                if !habitual(b) { out.append(Duplicate(first: a, second: b)); taken.insert(a.id); taken.insert(b.id) }
                break
            }
        }
        return out
    }

    public struct Fees: Hashable, Sendable { public let total: Decimal; public let items: [Transaction]; public init(total: Decimal, items: [Transaction]) { self.total = total; self.items = items } }

    public static func feesYearToDate(_ transactions: [Transaction], now: Date, calendar: Calendar = .current) -> Fees {
        guard let year = calendar.dateInterval(of: .year, for: now) else { return Fees(total: 0, items: []) }
        let items = transactions.filter { $0.isFee && year.holds($0.displayDate) && $0.displayDate <= now }.sorted { $0.displayDate > $1.displayDate }
        return Fees(total: items.reduce(0) { $0 + $1.magnitude }, items: items)
    }
}
