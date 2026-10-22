import Foundation

/// What a part of your life costs, month after month. Prices answer "what does this thing cost?"; this answers
/// "what does Groceries cost?" — the run of months, what a usual one looks like, and what moved against the month
/// that's actually comparable (the same month a year ago once there's a year, else the usual month).
public struct CategoryHistory: Sendable {
    public struct Month: Identifiable, Hashable, Sendable {
        public let start: Date
        public let total: Decimal
        public let count: Int
        public var id: Date { start }
        public init(start: Date, total: Decimal, count: Int) { self.start = start; self.total = total; self.count = count }
    }
    /// What the user can ask for; `all` names the years it actually has.
    public enum Range: Hashable, Sendable {
        case year, twoYears, all
        public var months: Int? { switch self { case .year: 12; case .twoYears: 24; case .all: nil } }
    }
    public struct Move: Identifiable, Hashable, Sendable {
        public let name: String
        public let merchantKey: String
        public let amount: Decimal
        public let count: Int
        /// Against the comparable month: nil when the merchant wasn't there at all (then `amount` is the whole story).
        public let was: Decimal?
        public let wasCount: Int?
        public var id: String { merchantKey }
        public var delta: Decimal { (amount - (was ?? 0)).roundedToCents }
        public var isNew: Bool { was == nil }
        public init(name: String, merchantKey: String, amount: Decimal, count: Int, was: Decimal?, wasCount: Int?) {
            self.name = name; self.merchantKey = merchantKey; self.amount = amount; self.count = count; self.was = was; self.wasCount = wasCount
        }
    }

    /// Oldest first, one per calendar month from the first charge to the month in view — gaps included, as zero.
    public var months: [Month]
    /// The median of the months that had a charge, excluding the one in view.
    public var usual: Decimal
    /// The month being looked at.
    public var current: Month
    /// The same month a year earlier, when the history reaches that far and it had charges.
    public var lastYear: Month?
    /// Merchants that moved against the comparable month, biggest change first.
    public var moves: [Move]
    /// How many whole years of history exist (0 when it's all inside one year).
    public var years: Int

    public var comparedToLastYear: Bool { lastYear != nil }
    /// What the current month is against its comparison: positive means more was spent.
    public var delta: Decimal { (current.total - (lastYear?.total ?? usual)).roundedToCents }
    /// Ranges worth offering: never one that would show the same bars as another.
    public var ranges: [Range] {
        var out: [Range] = [.year]
        if months.count > 12 { out.append(.twoYears) }
        if months.count > 24 { out.append(.all) }
        return out.count == 1 ? [] : out
    }
    public func months(in range: Range) -> [Month] {
        guard let n = range.months, months.count > n else { return months }
        return Array(months.suffix(n))
    }
}

public enum CategoryHistoryEngine {
    /// A month runs "over" when it's a quarter above the usual — the same rule a price uses to say it moved.
    public static let overThreshold = Decimal(0.25)

    public static func history(categoryID: String, transactions: [Transaction], now: Date, categories: CategorySet = .builtIn, calendar: Calendar = .current) -> CategoryHistory? {
        let rows = transactions.filter { ($0.kind == .spend || $0.kind == .untracked) && !$0.excluded && categories.resolve($0.categoryID).id == categoryID }
        guard !rows.isEmpty, let currentMonth = calendar.dateInterval(of: .month, for: now), let first = rows.map(\.displayDate).min(),
              var cursor = calendar.dateInterval(of: .month, for: first)?.start else { return nil }
        var months: [CategoryHistory.Month] = []
        while cursor <= currentMonth.start {
            guard let m = calendar.dateInterval(of: .month, for: cursor) else { break }
            let inMonth = rows.filter { m.holds($0.displayDate) }
            months.append(.init(start: m.start, total: inMonth.reduce(0) { $0 + $1.magnitude }.roundedToCents, count: inMonth.count))
            guard let next = calendar.date(byAdding: .month, value: 1, to: cursor) else { break }
            cursor = next
        }
        guard let current = months.last else { return nil }
        let earlier = months.dropLast().map(\.total).filter { $0 > 0 }.sorted()
        let usual = earlier.isEmpty ? current.total : earlier[earlier.count / 2]
        let lastYearStart = calendar.date(byAdding: .year, value: -1, to: current.start)
        let lastYear = lastYearStart.flatMap { s in months.first { calendar.isDate($0.start, equalTo: s, toGranularity: .month) } }.flatMap { $0.count > 0 ? $0 : nil }

        // What moved: this month's merchants against the comparable month's.
        let compare: DateInterval? = lastYear.flatMap { calendar.dateInterval(of: .month, for: $0.start) }
        let thisMonth = Dictionary(grouping: rows.filter { currentMonth.holds($0.displayDate) }) { $0.merchantKey }
        let then = compare.map { c in Dictionary(grouping: rows.filter { c.holds($0.displayDate) }) { $0.merchantKey } } ?? [:]
        var moves: [CategoryHistory.Move] = []
        for (key, group) in thisMonth {
            let amount = group.reduce(Decimal(0)) { $0 + $1.magnitude }.roundedToCents
            let before = then[key]
            // Without a year to compare, measure a merchant against its own usual month instead.
            let was: Decimal?, wasCount: Int?
            if compare != nil {
                was = before.map { $0.reduce(Decimal(0)) { $0 + $1.magnitude }.roundedToCents }
                wasCount = before?.count
            } else {
                let byMonth = Dictionary(grouping: rows.filter { $0.merchantKey == key && !currentMonth.holds($0.displayDate) }) { calendar.dateInterval(of: .month, for: $0.displayDate)?.start ?? $0.displayDate }
                let totals = byMonth.values.map { $0.reduce(Decimal(0)) { $0 + $1.magnitude } }.sorted()
                was = totals.isEmpty ? nil : totals[totals.count / 2].roundedToCents
                wasCount = totals.isEmpty ? nil : Int((Double(byMonth.values.reduce(0) { $0 + $1.count }) / Double(byMonth.count)).rounded())
            }
            moves.append(.init(name: group.max { $0.displayDate < $1.displayDate }?.merchant ?? key, merchantKey: key, amount: amount, count: group.count, was: was, wasCount: wasCount))
        }
        // Merchants that used to be here and have gone quiet count as movement too.
        for (key, group) in then where thisMonth[key] == nil {
            let was = group.reduce(Decimal(0)) { $0 + $1.magnitude }.roundedToCents
            moves.append(.init(name: group[0].merchant, merchantKey: key, amount: 0, count: 0, was: was, wasCount: group.count))
        }
        moves = moves.filter { abs($0.delta) >= max(Decimal(5), ($0.was ?? $0.amount) * Decimal(0.15)) }.sorted { abs($0.delta) > abs($1.delta) }

        let years = (calendar.dateComponents([.year], from: months[0].start, to: current.start).year ?? 0)
        return CategoryHistory(months: months, usual: usual, current: current, lastYear: lastYear, moves: Array(moves.prefix(5)), years: years)
    }

    /// The heads-up: this month is a quarter or more above what a comparable month costs.
    public static func overspendInsight(categoryID: String, name: String, history: CategoryHistory, now: Date, calendar: Calendar = .current) -> Insight? {
        let benchmark = history.lastYear?.total ?? history.usual
        guard benchmark > 0, history.current.total > benchmark * (1 + overThreshold) else { return nil }
        let over = (history.current.total - benchmark).roundedToCents
        let pct = Int((Double(truncating: (over / benchmark) as NSDecimalNumber) * 100).rounded())
        let against = history.comparedToLastYear ? "than the same month last year" : "than a usual month"
        return Insight(id: "category-over-\(categoryID)-\(calendar.component(.year, from: now))-\(calendar.component(.month, from: now))",
                       kind: .categoryOver, tone: .heads,
                       title: "\(name) is \(over.moneyString(cents: false)) over",
                       body: "\(history.current.total.moneyString(cents: false)) so far this month — \(pct)% more \(against) (\(benchmark.moneyString(cents: false))).", rank: 4)
    }
}

private func abs(_ d: Decimal) -> Decimal { d < 0 ? -d : d }
