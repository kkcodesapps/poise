import Foundation

/// Sunday's five cards: kept · biggest category and its merchant · one leak · what's coming · one positive.
public struct ReviewCard: Hashable, Sendable, Identifiable {
    public enum Tone: String, Sendable { case neutral, good, heads }
    public let id: String
    public let eyebrow: String
    public let value: String
    public let title: String
    public let body: String
    public let tone: Tone
    public init(id: String, eyebrow: String, value: String, title: String, body: String, tone: Tone) { self.id = id; self.eyebrow = eyebrow; self.value = value; self.title = title; self.body = body; self.tone = tone }
}

public enum WeeklyReview {
    public static func cards(transactions: [Transaction], streams: [RecurringStream], insights: [Insight], cashflow: [CashflowDay], verdict: Verdict, now: Date, calendar: Calendar = .current) -> [ReviewCard] {
        let weekEnd = calendar.startOfDay(for: now)
        let weekStart = calendar.date(byAdding: .day, value: -7, to: weekEnd)!
        let prevStart = calendar.date(byAdding: .day, value: -7, to: weekStart)!
        let week = DateInterval(start: weekStart, end: weekEnd.addingTimeInterval(86_400))
        let prev = DateInterval(start: prevStart, end: weekStart)
        func isSpend(_ t: Transaction) -> Bool { t.kind == .spend || t.kind == .untracked }
        func kept(_ i: DateInterval) -> Decimal {
            transactions.filter { i.contains($0.displayDate) }.reduce(0) { acc, t in
                acc + (t.kind == .income ? t.amount : isSpend(t) ? -t.magnitude : t.kind == .refund ? t.magnitude : 0)
            }
        }
        let thisKept = kept(week), lastKept = kept(prev)
        let diff = thisKept - lastKept
        var cards: [ReviewCard] = []
        cards.append(ReviewCard(id: "kept", eyebrow: "1 OF 5 · KEPT", value: thisKept.moneyString(cents: false), title: thisKept >= 0 ? "kept this week" : "spent beyond income this week",
                                body: diff >= 0 ? "That's \(diff.moneyString(cents: false)) more than last week." : "That's \((-diff).moneyString(cents: false)) less than last week.",
                                tone: diff >= 0 ? .good : .neutral))

        let weekSpend = transactions.filter { week.contains($0.displayDate) && isSpend($0) }
        let byCat = Dictionary(grouping: weekSpend) { $0.category ?? .other }.mapValues { $0.reduce(Decimal(0)) { $0 + $1.magnitude } }
        if let (cat, total) = byCat.max(by: { $0.value < $1.value }) {
            let merchants = Dictionary(grouping: weekSpend.filter { ($0.category ?? .other) == cat }) { $0.merchant }.mapValues { $0.reduce(Decimal(0)) { $0 + $1.magnitude } }
            let top = merchants.max(by: { $0.value < $1.value })
            cards.append(ReviewCard(id: "biggest", eyebrow: "2 OF 5 · BIGGEST", value: total.moneyString(cents: false), title: "\(cat.title)\(top.map { ", mostly \($0.key)" } ?? "")",
                                    body: top.map { "\($0.value.moneyString(cents: false)) at \($0.key) across \(merchants.count) merchant\(merchants.count == 1 ? "" : "s") this week." } ?? "", tone: .neutral))
        }
        if let leak = insights.first(where: { [.priceUp, .fee, .duplicate, .renewal].contains($0.kind) }) {
            cards.append(ReviewCard(id: "leak-\(leak.id)", eyebrow: "3 OF 5 · ONE LEAK", value: leak.kind == .fee ? "Fee" : leak.kind == .priceUp ? "Price up" : leak.kind == .duplicate ? "Twice?" : "Renewal", title: leak.title, body: leak.body, tone: .heads))
        } else {
            cards.append(ReviewCard(id: "leak-none", eyebrow: "3 OF 5 · LEAKS", value: "None", title: "No leaks this week", body: "Nothing recurring changed price and no fees were charged.", tone: .good))
        }
        let upcoming = cashflow.dropFirst().prefix(7).flatMap { day in day.lines.filter { $0.amount < 0 }.map { ($0, day.date) } }
        let total = upcoming.reduce(Decimal(0)) { $0 + (-$1.0.amount) }
        let crunch = cashflow.first { $0.isCrunch }
        cards.append(ReviewCard(id: "coming", eyebrow: "4 OF 5 · NEXT WEEK", value: total.moneyString(cents: false), title: upcoming.isEmpty ? "nothing due next week" : "due across \(upcoming.count) bill\(upcoming.count == 1 ? "" : "s")",
                                body: crunch.map { "Checking runs short on \($0.date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())) — move \((-$0.balanceAfter).moneyString(cents: false)) before then." }
                                    ?? (upcoming.map { "\($0.0.name) \((-$0.0.amount).moneyString(cents: true))" }.prefix(3).joined(separator: " · ")), tone: crunch == nil ? .neutral : .heads))
        let pct = Int((verdict.kept.onPacePercent * 100).rounded())
        cards.append(ReviewCard(id: "positive", eyebrow: "5 OF 5 · ONE GOOD THING", value: "\(max(0, pct))%", title: pct >= 20 ? "on pace to keep this month" : "kept so far this month",
                                body: pct >= 20 ? "Keep the same rhythm through payday and it holds." : "Every week you don't spend it, this number grows.", tone: pct >= 20 ? .good : .neutral))
        return cards
    }
}
