import Foundation

/// This month against last, projected to month-end, and what moved it.
public struct Pace: Hashable, Sendable {
    public struct Mover: Hashable, Sendable, Identifiable {
        public let categoryID: String
        public let name: String
        public let symbol: String
        public let thisMonth: Decimal
        public let lastMonth: Decimal
        public var delta: Decimal { thisMonth - lastMonth }
        public var id: String { categoryID }
    }
    public struct Point: Hashable, Sendable { public let day: Int; public let thisMonth: Decimal?; public let lastMonth: Decimal? }

    public let spendSoFar: Decimal
    public let projected: Decimal
    public let lastMonthTotal: Decimal
    public let lastMonthSameDay: Decimal
    public let movers: [Mover]          // sorted by |delta|, largest first
    public let needs: Decimal
    public let wants: Decimal
    public let cumulative: [Point]      // day 1…daysInMonth, cumulative spend
    public let dayOfMonth: Int
    public let daysInMonth: Int

    public var overLastMonth: Decimal { projected - lastMonthTotal }
    public var topMover: Mover? { movers.first { $0.delta > 0 } }
}

public enum PaceEngine {
    public static func pace(transactions: [Transaction], streams: [RecurringStream], now: Date, calendar: Calendar = .current, categories: CategorySet = .builtIn) -> Pace {
        let month = calendar.dateInterval(of: .month, for: now)!
        let lastMonthStart = calendar.date(byAdding: .month, value: -1, to: month.start)!
        let lastMonth = DateInterval(start: lastMonthStart, end: month.start)
        let dayOfMonth = calendar.component(.day, from: now)
        let daysInMonth = calendar.range(of: .day, in: .month, for: now)?.count ?? 30

        func isSpend(_ t: Transaction) -> Bool { (t.kind == .spend || t.kind == .untracked) && categories.lens(t.categoryID) != .kept }
        func net(_ rows: [Transaction]) -> Decimal { rows.reduce(0) { $0 + (isSpend($1) ? $1.magnitude : $1.kind == .refund ? -$1.magnitude : 0) } }
        let thisRows = transactions.filter { month.contains($0.displayDate) && $0.displayDate <= now && (isSpend($0) || $0.kind == .refund) }
        let lastRows = transactions.filter { lastMonth.contains($0.displayDate) && (isSpend($0) || $0.kind == .refund) }
        let sameDayCutoff = calendar.date(byAdding: .day, value: dayOfMonth, to: lastMonthStart)!
        let lastSameDayRows = lastRows.filter { $0.displayDate < sameDayCutoff }

        let spendSoFar = net(thisRows)
        let wants = thisRows.filter { isSpend($0) && categories.lens($0.categoryID) == .wants }.reduce(0) { $0 + $1.magnitude }
        let needs = thisRows.filter { isSpend($0) && categories.lens($0.categoryID) == .needs }.reduce(0) { $0 + $1.magnitude }
        let avgDailyWants = wants / Decimal(max(1, dayOfMonth))
        let remainingBills = streams.filter { $0.kind != .income }.reduce(Decimal(0)) { acc, s in
            acc + s.amount * Decimal(s.occurrences(after: now, through: month.end.addingTimeInterval(-1), calendar: calendar).count)
        }
        let projected = (spendSoFar + avgDailyWants * Decimal(max(0, daysInMonth - dayOfMonth)) + remainingBills).roundedToCents

        var byCat: [String: (Decimal, Decimal)] = [:]
        for t in thisRows where isSpend(t) { byCat[categories.resolve(t.categoryID).id, default: (0, 0)].0 += t.magnitude }
        for t in lastRows where isSpend(t) { byCat[categories.resolve(t.categoryID).id, default: (0, 0)].1 += t.magnitude }
        let movers = byCat.map { id, v in Pace.Mover(categoryID: id, name: categories.name(id), symbol: categories.symbol(id), thisMonth: v.0, lastMonth: v.1) }
            .sorted { abs($0.delta) > abs($1.delta) }

        var points: [Pace.Point] = []
        var runThis: Decimal = 0, runLast: Decimal = 0
        for day in 1...daysInMonth {
            let d = calendar.date(byAdding: .day, value: day - 1, to: month.start)!
            let l = calendar.date(byAdding: .day, value: day - 1, to: lastMonthStart)!
            runThis += net(thisRows.filter { calendar.isDate($0.displayDate, inSameDayAs: d) })
            runLast += net(lastRows.filter { calendar.isDate($0.displayDate, inSameDayAs: l) })
            points.append(Pace.Point(day: day, thisMonth: day <= dayOfMonth ? runThis : nil, lastMonth: runLast))
        }
        return Pace(spendSoFar: spendSoFar, projected: projected, lastMonthTotal: net(lastRows), lastMonthSameDay: net(lastSameDayRows),
                    movers: movers, needs: needs, wants: wants, cumulative: points, dayOfMonth: dayOfMonth, daysInMonth: daysInMonth)
    }
}

private func abs(_ d: Decimal) -> Decimal { d < 0 ? -d : d }

public extension Decimal {
    /// Money math ends here: two places, bankers-free (plain) rounding.
    var roundedToCents: Decimal {
        var value = self, result = Decimal()
        NSDecimalRound(&result, &value, 2, .plain)
        return result
    }
}
