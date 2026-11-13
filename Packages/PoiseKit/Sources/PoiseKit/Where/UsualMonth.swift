import Foundation

/// What a month usually costs, for measuring one month's categories against the months before it. Usual is the average
/// of up to three earlier months; low and high are how far those months ranged. A month still in progress is measured
/// against the same days of those months, so the 6th isn't compared with a whole month.
public struct UsualMonth: Hashable, Sendable {
    public enum Standing: Hashable, Sendable { case over, under, within }
    public struct Entry: Hashable, Sendable {
        public let usual: Decimal
        public let low: Decimal
        public let high: Decimal
    }

    /// How many earlier months this was drawn from.
    public let months: Int
    public let total: Decimal
    public let inProgress: Bool
    let byCategory: [String: Entry]

    /// A category none of the earlier months had usually costs nothing.
    public func entry(_ categoryID: String) -> Entry { byCategory[categoryID] ?? Entry(usual: 0, low: 0, high: 0) }
    public func gap(_ row: Breakdown.Row) -> Decimal { (row.amount - entry(row.categoryID).usual).roundedToCents }

    /// Over or under only once it leaves the range the earlier months covered. With no history there's no range to leave.
    public func standing(_ row: Breakdown.Row) -> Standing {
        let e = entry(row.categoryID)
        guard e.high > 0 else { return .within }
        if row.amount > e.high { return .over }
        if row.amount < e.low { return .under }
        return .within
    }

    /// Biggest gap first. Other goes last: it's a catch-all, so its usual is whatever odd charges landed there, and the
    /// gap says nothing about a habit.
    public func ranked(_ rows: [Breakdown.Row]) -> [Breakdown.Row] {
        let byGap = rows.sorted { abs(gap($0)) > abs(gap($1)) }
        return byGap.filter { $0.categoryID != SpendCategory.other.rawValue } + byGap.filter { $0.categoryID == SpendCategory.other.rawValue }
    }

    /// One dollar scale for every row, either side of usual, reaching the furthest dot or range and rounded up to $100.
    /// Other doesn't stretch it, for the same reason it ranks last: one odd charge would flatten every real category.
    public func scale(_ rows: [Breakdown.Row]) -> Decimal {
        var furthest: Decimal = 0
        for r in rows where r.categoryID != SpendCategory.other.rawValue {
            let e = entry(r.categoryID)
            furthest = max(furthest, abs(gap(r)), abs(e.low - e.usual), abs(e.high - e.usual))
        }
        let hundreds = NSDecimalNumber(decimal: furthest / 100).doubleValue.rounded(.up)
        return Decimal(max(hundreds, 1) * 100)
    }

    public static func compute(transactions: [Transaction], window: DateInterval, now: Date, categories: CategorySet = .builtIn, calendar: Calendar = .current, lookback: Int = 3) -> UsualMonth? {
        guard let first = transactions.map(\.displayDate).min() else { return nil }
        let inProgress = window.holds(now)
        let elapsed = inProgress ? (calendar.dateComponents([.day], from: window.start, to: now).day ?? 0) + 1 : nil

        var earlier: [Breakdown] = []
        for n in 1...lookback {
            let w = Periods.shift(window, .month, by: -n, calendar: calendar)
            guard w.end > first else { break }
            var rows = transactions
            if let elapsed, let cut = calendar.date(byAdding: .day, value: elapsed, to: w.start), cut < w.end {
                rows = rows.filter { $0.displayDate < cut }
            }
            let b = CategoryBreakdown.compute(transactions: rows, period: .month, window: w, now: now, categories: categories, calendar: calendar)
            if b.total > 0 { earlier.append(b) }
        }
        guard !earlier.isEmpty else { return nil }

        let count = Decimal(earlier.count)
        var byCategory: [String: Entry] = [:]
        for id in Set(earlier.flatMap { $0.rows.map(\.categoryID) }) {
            // A month without the category spent nothing on it, and that counts toward the usual.
            let amounts = earlier.map { b in b.rows.first { $0.categoryID == id }?.amount ?? 0 }
            byCategory[id] = Entry(usual: (amounts.reduce(0, +) / count).roundedToCents, low: amounts.min() ?? 0, high: amounts.max() ?? 0)
        }
        return UsualMonth(months: earlier.count, total: (earlier.reduce(0) { $0 + $1.total } / count).roundedToCents, inProgress: inProgress, byCategory: byCategory)
    }
}

public extension Breakdown {
    /// The window day by day, for the calendar. A refund counts against its day.
    func days(calendar: Calendar = .current) -> [SliceTotal] {
        let all = slices.flatMap(\.transactions)
        return Periods.slices(window, .week, calendar: calendar).map { s in
            let rows = all.filter { s.interval.holds($0.displayDate) }
            let amount = rows.reduce(Decimal(0)) { $0 + ($1.kind == .refund ? -$1.magnitude : $1.magnitude) }
            return SliceTotal(slice: s, amount: amount.roundedToCents, transactions: rows)
        }
    }
}
