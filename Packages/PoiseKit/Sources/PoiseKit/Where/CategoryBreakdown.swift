import Foundation

/// Where the money went in a period: categories ranked, share and change, and the period sliced for the strip.
public struct Breakdown: Hashable, Sendable {
    public struct Row: Hashable, Sendable, Identifiable {
        public let categoryID: String
        public let name: String
        public let symbol: String
        public let lens: Lens
        public let amount: Decimal
        public let count: Int
        public let share: Double
        /// nil when there was nothing in the previous period (shown as "new").
        public let delta: Decimal?
        public var id: String { categoryID }
    }
    public struct SliceTotal: Hashable, Sendable, Identifiable {
        public let slice: Slice
        public let amount: Decimal
        public let transactions: [Transaction]
        public var id: Date { slice.id }
    }
    public let window: DateInterval
    public let total: Decimal
    public let previousTotal: Decimal
    public let rows: [Row]
    public let needs: Decimal
    public let wants: Decimal
    public let slices: [SliceTotal]
    public let count: Int
    public var delta: Decimal { total - previousTotal }
}

public enum CategoryBreakdown {
    /// Net spend per category: spend + untracked − refunds. A refund only nets here when the charge it reverses is in the
    /// same window (a September refund of an August flight belongs to August's story, not September's). Kept-lens categories are excluded.
    public static func compute(transactions: [Transaction], period: Period, window: DateInterval, now: Date, categories: CategorySet = .builtIn, calendar: Calendar = .current) -> Breakdown {
        let previous = Periods.comparable(previousOf: window, period, now: now, calendar: calendar)
        let byID = Dictionary(uniqueKeysWithValues: transactions.map { ($0.id, $0) })
        func refundCounts(_ t: Transaction, in interval: DateInterval) -> Bool {
            guard let pair = t.pairID, let original = byID[pair] else { return false }
            return interval.contains(original.displayDate)
        }
        func counts(_ t: Transaction, in interval: DateInterval) -> Bool {
            guard categories.lens(t.categoryID) != .kept else { return false }
            switch t.kind {
            case .spend, .untracked: return true
            case .refund: return refundCounts(t, in: interval)
            default: return false
            }
        }
        func signed(_ t: Transaction) -> Decimal { t.kind == .refund ? -t.magnitude : t.magnitude }
        let inWindow = transactions.filter { window.contains($0.displayDate) && counts($0, in: window) }
        let inPrevious = transactions.filter { previous.contains($0.displayDate) && counts($0, in: previous) }

        var byCat: [String: (amount: Decimal, count: Int)] = [:]
        for t in inWindow { let id = categories.resolve(t.categoryID).id; byCat[id, default: (0, 0)].amount += signed(t); if t.kind != .refund { byCat[id, default: (0, 0)].count += 1 } }
        var prevByCat: [String: Decimal] = [:]
        for t in inPrevious { prevByCat[categories.resolve(t.categoryID).id, default: 0] += signed(t) }

        let total = byCat.values.reduce(0) { $0 + $1.amount }
        let previousTotal = prevByCat.values.reduce(0) { $0 + $1 }
        let rows = byCat.filter { $0.value.count > 0 }.map { id, v -> Breakdown.Row in
            let c = categories.resolve(id)
            let prev = prevByCat[id]
            return Breakdown.Row(categoryID: id, name: c.name, symbol: c.symbol, lens: c.lens, amount: v.amount.roundedToCents, count: v.count,
                                 share: total > 0 ? max(0, NSDecimalNumber(decimal: v.amount / total).doubleValue) : 0,
                                 delta: (prev == nil || prev == 0) ? nil : (v.amount - prev!).roundedToCents)
        }.sorted { $0.amount > $1.amount }
        let needs = rows.filter { $0.lens == .needs }.reduce(0) { $0 + $1.amount }
        let wants = rows.filter { $0.lens == .wants }.reduce(0) { $0 + $1.amount }
        let slices = Periods.slices(window, period, calendar: calendar).map { s -> Breakdown.SliceTotal in
            let rowsIn = inWindow.filter { s.interval.contains($0.displayDate) }.sorted { $0.displayDate > $1.displayDate }
            return Breakdown.SliceTotal(slice: s, amount: rowsIn.reduce(0) { $0 + signed($1) }.roundedToCents, transactions: rowsIn)
        }
        return Breakdown(window: window, total: total.roundedToCents, previousTotal: previousTotal.roundedToCents, rows: rows, needs: needs, wants: wants, slices: slices, count: inWindow.filter { $0.kind != .refund }.count)
    }

    /// Merchants inside one category for the window, ranked.
    public struct Merchant: Hashable, Sendable, Identifiable { public let name: String; public let amount: Decimal; public let count: Int; public var id: String { name }; public var average: Decimal { count > 0 ? (amount / Decimal(count)).roundedToCents : 0 } }
    public static func merchants(in categoryID: String, transactions: [Transaction], window: DateInterval, categories: CategorySet = .builtIn) -> [Merchant] {
        let rows = transactions.filter { window.contains($0.displayDate) && ($0.kind == .spend || $0.kind == .untracked) && categories.resolve($0.categoryID).id == categoryID }
        let groups = Dictionary(grouping: rows) { $0.merchantKey }
        return groups.values.map { g in Merchant(name: g[0].merchant, amount: g.reduce(0) { $0 + $1.magnitude }.roundedToCents, count: g.count) }.sorted { $0.amount > $1.amount }
    }
}
