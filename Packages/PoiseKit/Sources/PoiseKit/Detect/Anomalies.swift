import Foundation

/// The things worth a heads-up that aren't about the budget: double charges and fees.
public enum Anomalies {
    public struct Duplicate: Hashable, Sendable { public let first: Transaction; public let second: Transaction; public init(first: Transaction, second: Transaction) { self.first = first; self.second = second } }

    /// Same merchant, same amount, within 48 hours, both spend.
    public static func duplicates(in transactions: [Transaction]) -> [Duplicate] {
        let spend = transactions.filter { $0.kind == .spend }.sorted { $0.displayDate < $1.displayDate }
        var out: [Duplicate] = []
        for (i, a) in spend.enumerated() {
            for b in spend[(i + 1)...] {
                let gap = b.displayDate.timeIntervalSince(a.displayDate)
                if gap > 48 * 3600 { break }
                if b.merchantKey == a.merchantKey, b.magnitude == a.magnitude { out.append(Duplicate(first: a, second: b)); break }
            }
        }
        return out
    }

    public struct Fees: Hashable, Sendable { public let total: Decimal; public let items: [Transaction]; public init(total: Decimal, items: [Transaction]) { self.total = total; self.items = items } }

    public static func feesYearToDate(_ transactions: [Transaction], now: Date, calendar: Calendar = .current) -> Fees {
        guard let year = calendar.dateInterval(of: .year, for: now) else { return Fees(total: 0, items: []) }
        let items = transactions.filter { $0.isFee && year.contains($0.displayDate) && $0.displayDate <= now }.sorted { $0.displayDate > $1.displayDate }
        return Fees(total: items.reduce(0) { $0 + $1.magnitude }, items: items)
    }
}
