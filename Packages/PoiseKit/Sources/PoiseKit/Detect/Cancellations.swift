import Foundation

/// Subscriptions the user said they cancelled, and ones that went quiet on their own and came back.
public enum Cancellations {
    /// The charge that shouldn't have happened: a cancelled stream's merchant billing again after the cancel date.
    /// One insight per charge, at the top of everything.
    public static func chargedAfterCancel(streams: [RecurringStream], cancelled: [String: Date], transactions: [Transaction], calendar: Calendar = .current) -> [Insight] {
        var out: [Insight] = []
        for (id, date) in cancelled {
            guard let s = streams.first(where: { $0.id == id }) else { continue }
            let since = calendar.startOfDay(for: date)
            let key = Transaction.merchantKey(s.merchant)
            let hits = transactions.filter { ($0.kind == .spend || $0.kind == .untracked) && $0.amount < 0 && $0.merchantKey == key && $0.displayDate >= since && abs($0.magnitude - s.amount) <= s.amount * Decimal(0.25) }
                .sorted { $0.displayDate > $1.displayDate }
            guard let latest = hits.first else { continue }
            // One card per subscription; a fresh charge makes a fresh card, so it can't be waved away once for good.
            let more = hits.count > 1 ? " That makes \(hits.count) charges since." : ""
            out.append(Insight(id: "cancelled-\(id)-\(latest.id)", kind: .cancelledCharge, tone: .heads, title: "\(s.merchant) charged you after you cancelled",
                               body: "\(latest.magnitude.moneyString(cents: true)) on \(latest.displayDate.formatted(.dateTime.month(.abbreviated).day())) — you marked it cancelled \(since.formatted(.dateTime.month(.abbreviated).day())).\(more) Dispute it, or cancel again.", rank: 0))
        }
        return out
    }

    /// A stream that had gone quiet for two periods and charged again inside the last week.
    public static func returned(streams: [RecurringStream], now: Date, calendar: Calendar = .current) -> [Insight] {
        streams.compactMap { s in
            guard let r = s.returnedAt, (calendar.dateComponents([.day], from: r, to: now).day ?? 99) <= 7, s.kind != .income else { return nil }
            return Insight(id: "returned-\(s.id)-\(Int(r.timeIntervalSince1970))", kind: .streamReturned, tone: .neutral, title: "\(s.merchant) is back",
                           body: "\(s.amount.moneyString(cents: true)) on \(r.formatted(.dateTime.month(.abbreviated).day())) after a quiet stretch. Meant to? It's counting again.", rank: 2)
        }
    }
}

private func abs(_ d: Decimal) -> Decimal { d < 0 ? -d : d }
