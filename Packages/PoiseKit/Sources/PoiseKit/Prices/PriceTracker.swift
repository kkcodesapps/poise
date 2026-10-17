import Foundation

/// What you pay for the things you buy again. Banks hand over totals, not receipts, so an item is either a merchant
/// whose charges repeat at about the same price (a burrito, a fill-up, a plan) or a name the user gave to charges
/// ("Naked Whey Protein", bought seven times through Amazon). Each carries its run of prices and what they say.
public struct PriceItem: Identifiable, Hashable, Sendable {
    public struct Purchase: Identifiable, Hashable, Sendable {
        public let id: String          // the transaction
        public let date: Date
        public let price: Decimal
        public let merchant: String
        public let accountID: String
        public let pending: Bool
        public init(id: String, date: Date, price: Decimal, merchant: String, accountID: String, pending: Bool) {
            self.id = id; self.date = date; self.price = price; self.merchant = merchant; self.accountID = accountID; self.pending = pending
        }
    }
    public enum Source: String, Hashable, Sendable { case merchant, named, plan }
    public enum Direction: Hashable, Sendable { case up, down, steady }

    public let id: String              // "merchant|<merchant key>" or "named|<name key>"
    public let source: Source
    public var name: String
    public var merchant: String        // the latest purchase's merchant, as the bank spells it
    public var merchantKey: String
    public var categoryID: String?
    public var logoURL: String?
    /// Oldest first.
    public var purchases: [Purchase]
    /// The median of the latest twelve settled purchases — what this usually costs.
    public var usual: Decimal
    public var lowest: Decimal
    public var highest: Decimal
    /// The last price that differed from the latest one, when there is one.
    public var previous: Decimal?
    /// When `previous` gave way to the current price.
    public var changedAt: Date?
    /// Set by the app from the user's watches.
    public var tracked = false
    /// Prices cluster (most within ±25 % of the median) — a usual price means something. Groceries and usage don't.
    public var steady = true
    /// For a plan: the stream it follows. For usage: the plan it sits on top of.
    public var streamID: String?
    /// "plan" / "usage" when a merchant has both, so the two runs read apart: "Cursor · plan", "Cursor · usage".
    public var planSuffix: String?

    public var last: Decimal { purchases.last?.price ?? 0 }
    public var average: Decimal { purchases.isEmpty ? 0 : (purchases.reduce(Decimal(0)) { $0 + $1.price } / Decimal(purchases.count)).roundedToCents }
    public var count: Int { purchases.count }
    public var firstSeen: Date { purchases.first?.date ?? .distantPast }
    public var lastSeen: Date { purchases.last?.date ?? .distantPast }
    public var delta: Decimal { (last - usual).roundedToCents }
    public var deltaPercent: Double { usual > 0 ? Double(truncating: (delta / usual) as NSDecimalNumber) : 0 }
    public var direction: Direction {
        guard steady, PriceTracker.moved(last, from: usual) else { return .steady }
        return delta > 0 ? .up : .down
    }
    /// Bought within the last 45 days at a price that isn't the usual one.
    public func movedLately(now: Date, calendar: Calendar = .current) -> Bool {
        direction != .steady && (calendar.dateComponents([.day], from: lastSeen, to: now).day ?? 99) <= 45
    }
}

public enum PriceTracker {
    /// Anything bought twice is worth a run.
    public static let minimumMerchantPurchases = 2
    public static let minimumNamedPurchases = 2

    /// A price "moved" when it differs from the usual by at least 3 % and fifty cents.
    public static func moved(_ price: Decimal, from usual: Decimal) -> Bool {
        let diff = abs(price - usual)
        return diff >= max(Decimal(0.5), usual * Decimal(0.03))
    }

    /// The key a display name groups under: letters, digits and single spaces.
    public static func nameKey(_ name: String) -> String {
        name.lowercased().unicodeScalars.map { CharacterSet.alphanumerics.contains($0) ? Character($0) : " " }
            .reduce(into: "") { acc, c in if c != " " || (acc.last != " " && !acc.isEmpty) { acc.append(c) } }
            .trimmingCharacters(in: .whitespaces)
    }

    /// Every run worth a chart: named charges, a subscription's plan (the stream's own rows), and each merchant's remaining
    /// charges — steady or not. A merchant with a plan gets its other charges as a "usage" run.
    public static func items(in transactions: [Transaction], streams: [RecurringStream] = [], now: Date, calendar: Calendar = .current) -> [PriceItem] {
        let rows = transactions.filter { ($0.kind == .spend || $0.kind == .untracked) && $0.amount < 0 && !$0.excluded }
        var named: [String: [Transaction]] = [:], byMerchant: [String: [Transaction]] = [:]
        let planRows = Dictionary(uniqueKeysWithValues: streams.filter { $0.kind != .income }.map { ($0.id, Set($0.transactionIDs)) })
        let inPlan = Set(planRows.values.flatMap { $0 })
        for t in rows {
            if let n = t.displayName, !n.trimmingCharacters(in: .whitespaces).isEmpty { named[nameKey(n), default: []].append(t) }
            else if !inPlan.contains(t.id) { byMerchant[t.merchantKey, default: []].append(t) }
        }
        var out: [PriceItem] = []
        for (key, group) in named where group.count >= minimumNamedPurchases {
            if let item = build(id: "named|\(key)", source: .named, name: group.max { $0.displayDate < $1.displayDate }!.displayName ?? key, group: group, calendar: calendar) { out.append(item) }
        }
        let byID = Dictionary(uniqueKeysWithValues: rows.map { ($0.id, $0) })
        for s in streams where s.kind != .income {
            let group = s.transactionIDs.compactMap { byID[$0] }.filter { ($0.displayName ?? "").trimmingCharacters(in: .whitespaces).isEmpty }   // named rows already have their run
            guard group.count >= 2 else { continue }
            let hasOthers = !(byMerchant[Transaction.merchantKey(s.merchant)] ?? []).isEmpty
            if var item = build(id: "plan|\(s.id)", source: .plan, name: s.merchant, group: group, calendar: calendar) {
                item.streamID = s.id; item.planSuffix = hasOthers ? "plan" : nil
                out.append(item)
            }
        }
        for (key, group) in byMerchant where group.count >= minimumMerchantPurchases {
            let latest = group.max { $0.displayDate < $1.displayDate }!
            if var item = build(id: "merchant|\(key)", source: .merchant, name: latest.merchant, group: group, calendar: calendar) {
                item.steady = sellsOneThing(group)
                if let plan = streams.first(where: { $0.kind != .income && Transaction.merchantKey($0.merchant) == key }) { item.streamID = plan.id; item.planSuffix = "usage"; item.steady = false }   // pay-as-you-go varies by nature
                out.append(item)
            }
        }
        return out.sorted { $0.lastSeen > $1.lastSeen }
    }

    /// For items the user is tracking: the latest purchase, when it landed inside a week at a price off the usual one.
    public static func insights(_ items: [PriceItem], now: Date, calendar: Calendar = .current) -> [Insight] {
        items.compactMap { item in
            guard item.tracked, item.direction != .steady, let last = item.purchases.last,
                  (calendar.dateComponents([.day], from: last.date, to: now).day ?? 99) <= 7 else { return nil }
            let up = item.direction == .up
            let since = item.changedAt.map { " since \($0.formatted(.dateTime.month(.wide)))" } ?? ""
            return Insight(id: "price-item-\(item.id)-\(last.id)", kind: .priceMoved, tone: up ? .heads : .good,
                           title: "\(item.name) · \(item.last.moneyString(cents: true)), usually \(item.usual.moneyString(cents: true))",
                           body: "\(up ? "Up" : "Down") \(abs(item.delta).moneyString(cents: true))\(since) — \(Int((abs(item.deltaPercent) * 100).rounded()))% \(up ? "more" : "less") for the same thing.", rank: up ? 3 : 6)
        }
    }

    /// A merchant that charges about the same each time is selling one thing; a grocery store isn't.
    static func sellsOneThing(_ group: [Transaction]) -> Bool {
        let recent = group.sorted { $0.displayDate > $1.displayDate }.prefix(12).map(\.magnitude)
        guard let median = median(Array(recent)), median > 0 else { return false }
        let near = recent.filter { abs($0 - median) <= median * Decimal(0.25) }.count
        return Double(near) / Double(recent.count) >= 0.6
    }

    static func median(_ values: [Decimal]) -> Decimal? {
        guard !values.isEmpty else { return nil }
        let s = values.sorted()
        return s.count % 2 == 1 ? s[s.count / 2] : ((s[s.count / 2 - 1] + s[s.count / 2]) / 2).roundedToCents
    }

    static func build(id: String, source: PriceItem.Source, name: String, group: [Transaction], calendar: Calendar) -> PriceItem? {
        let sorted = group.sorted { ($0.displayDate, $0.id) < ($1.displayDate, $1.id) }
        let purchases = sorted.map { PriceItem.Purchase(id: $0.id, date: $0.displayDate, price: $0.magnitude, merchant: $0.merchant, accountID: $0.accountID, pending: $0.pending) }
        let settled = sorted.filter { !$0.pending }.suffix(12).map(\.magnitude)
        guard let usual = median(settled.isEmpty ? sorted.suffix(12).map(\.magnitude) : Array(settled)), let latest = sorted.last else { return nil }
        let prices = purchases.map(\.price)
        var previous: Decimal?, changedAt: Date?
        for p in purchases.reversed() where p.price != latest.magnitude { previous = p.price; break }
        if previous != nil, let firstAtCurrent = purchases.lastIndex(where: { $0.price != latest.magnitude }).map({ purchases[$0 + 1] }) { changedAt = firstAtCurrent.date }
        return PriceItem(id: id, source: source, name: name, merchant: latest.merchant, merchantKey: latest.merchantKey, categoryID: latest.categoryID, logoURL: latest.logoURL,
                         purchases: purchases, usual: usual, lowest: prices.min() ?? 0, highest: prices.max() ?? 0, previous: previous, changedAt: changedAt)
    }
}

private func abs(_ d: Decimal) -> Decimal { d < 0 ? -d : d }
