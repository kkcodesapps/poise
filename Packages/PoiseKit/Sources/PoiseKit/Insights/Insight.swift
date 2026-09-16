import Foundation

/// The one thing worth saying. Ranked so Home shows the top one and Leaks / Pace / Review get the rest.
public struct Insight: Hashable, Sendable, Identifiable {
    public enum Kind: String, Sendable, Codable { case crunch, duplicate, priceUp, fee, paceOverrun, positive, newStream, renewal }
    public enum Tone: String, Sendable { case heads, neutral, good }

    public let id: String
    public let kind: Kind
    public let tone: Tone
    public let title: String
    public let body: String
    public let rank: Int

    public init(id: String, kind: Kind, tone: Tone, title: String, body: String, rank: Int) {
        self.id = id; self.kind = kind; self.tone = tone; self.title = title; self.body = body; self.rank = rank
    }
}

public enum InsightEngine {
    public struct Input: Sendable {
        public var verdict: Verdict
        public var pace: Pace
        public var streams: [RecurringStream]
        public var transactions: [Transaction]
        public var now: Date
        public var acknowledged: Set<String>
        public var calendar: Calendar
        public init(verdict: Verdict, pace: Pace, streams: [RecurringStream], transactions: [Transaction], now: Date, acknowledged: Set<String> = [], calendar: Calendar = .current) {
            self.verdict = verdict; self.pace = pace; self.streams = streams; self.transactions = transactions; self.now = now; self.acknowledged = acknowledged; self.calendar = calendar
        }
    }

    public static func rank(_ input: Input) -> [Insight] {
        var out: [Insight] = []
        let cal = input.calendar
        let money = { (d: Decimal) -> String in d.moneyString(cents: false) }

        if let crunch = input.verdict.ahead.crunch {
            let day = crunch.date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
            out.append(Insight(id: "crunch-\(crunch.date.timeIntervalSince1970)", kind: .crunch, tone: .heads,
                               title: "Checking runs short on \(day)", body: "Move \(money(crunch.shortfall)) from savings before then and every bill clears.", rank: 1))
        }
        for d in Anomalies.duplicates(in: input.transactions) {
            out.append(Insight(id: "dup-\(d.second.id)", kind: .duplicate, tone: .heads, title: "Charged twice at \(d.first.merchant)?",
                               body: "\(d.first.magnitude.moneyString(cents: true)) twice within two days. Worth a look before it posts.", rank: 2))
        }
        for s in input.streams where s.priceWentUp {
            out.append(Insight(id: "price-\(s.id)", kind: .priceUp, tone: .heads, title: "\(s.merchant) went up \((s.amount - (s.previousAmount ?? s.amount)).moneyString(cents: true))",
                               body: "From \((s.previousAmount ?? 0).moneyString(cents: true)) to \(s.amount.moneyString(cents: true)) — want to review it?", rank: 3))
        }
        let fees = Anomalies.feesYearToDate(input.transactions, now: input.now, calendar: cal)
        if let latest = fees.items.first, (cal.dateComponents([.day], from: latest.displayDate, to: input.now).day ?? 99) <= 7 {
            out.append(Insight(id: "fee-\(latest.id)", kind: .fee, tone: .heads, title: "\(latest.magnitude.moneyString(cents: true)) fee at \(latest.merchant)",
                               body: "\(money(fees.total)) in fees this year so far.", rank: 4))
        }
        if let mover = input.pace.topMover, input.pace.overLastMonth > 0, mover.delta > 0 {
            out.append(Insight(id: "pace-\(mover.category.rawValue)-\(cal.component(.month, from: input.now))", kind: .paceOverrun, tone: .neutral,
                               title: "\(mover.category.title) is \(money(mover.delta)) over last month's pace",
                               body: "On pace for \(money(input.pace.projected)) — \(money(input.pace.overLastMonth)) over last month.", rank: 5))
        }
        if input.verdict.kept.onPacePercent >= 0.3 {
            out.append(Insight(id: "positive-\(cal.component(.month, from: input.now))", kind: .positive, tone: .good,
                               title: "On pace to keep \(Int((input.verdict.kept.onPacePercent * 100).rounded()))% this month",
                               body: "\(money(input.verdict.kept.keptSoFar)) kept so far. Keep the same rhythm through payday and it holds.", rank: 6))
        }
        for s in input.streams where s.kind == .subscription {
            let ageDays = cal.dateComponents([.day], from: s.lastSeen, to: input.now).day ?? 0
            if ageDays <= 3, s.previousAmount == nil, input.transactions.filter({ $0.merchantKey == Transaction.merchantKey(s.merchant) && $0.kind == .spend }).count == 2 {
                out.append(Insight(id: "new-\(s.id)", kind: .newStream, tone: .neutral, title: "New recurring charge: \(s.merchant)",
                                   body: "\(s.amount.moneyString(cents: true)) \(s.cadence.label). Poise will track it from here.", rank: 7))
            }
        }
        for s in input.streams where s.cadence == .annual {
            let days = cal.dateComponents([.day], from: cal.startOfDay(for: input.now), to: s.nextExpected).day ?? 99
            if (0...14).contains(days) {
                out.append(Insight(id: "renewal-\(s.id)-\(cal.component(.year, from: s.nextExpected))", kind: .renewal, tone: .neutral,
                                   title: "\(s.merchant) renews in \(days) day\(days == 1 ? "" : "s")", body: "\(s.amount.moneyString(cents: true)) yearly. Cancel before then if you don't want it.", rank: 8))
            }
        }
        return out.filter { !input.acknowledged.contains($0.id) }.sorted { $0.rank < $1.rank }
    }
}

public extension Cadence {
    var label: String {
        switch self {
        case .weekly: "weekly"
        case .biweekly: "every two weeks"
        case .monthly: "monthly"
        case .quarterly: "quarterly"
        case .annual: "yearly"
        }
    }
}

public extension Decimal {
    /// "$1,240" or "$62.40". Minus sign is the typographic one.
    func moneyString(cents: Bool) -> String {
        let f = NumberFormatter()
        f.numberStyle = .currency; f.currencyCode = "USD"; f.minusSign = "−"
        f.maximumFractionDigits = cents ? 2 : 0; f.minimumFractionDigits = cents ? 2 : 0
        return f.string(from: self as NSDecimalNumber) ?? "\(self)"
    }
}
