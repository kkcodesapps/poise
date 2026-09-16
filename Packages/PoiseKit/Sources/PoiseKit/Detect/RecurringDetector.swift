import Foundation

/// Finds subscriptions, bills and paychecks from the transaction history — no configuration, no provider add-on.
public enum RecurringDetector {
    /// Cadence buckets in days. A stream needs at least two occurrences (three for weekly) whose intervals land in one bucket
    /// and whose amounts stay within ±15% of the median.
    static let buckets: [(Cadence, ClosedRange<Int>, minCount: Int)] = [
        (.weekly, 5...9, 3), (.biweekly, 12...16, 2), (.monthly, 26...35, 2), (.quarterly, 80...100, 2), (.annual, 350...380, 2),
    ]

    public static func detect(_ transactions: [Transaction], now: Date, calendar: Calendar = .current) -> [RecurringStream] {
        let eligible = transactions.filter { !$0.pending && ($0.kind == .spend || $0.kind == .income) }
        let groups = Dictionary(grouping: eligible) { "\($0.kind.rawValue)|\($0.merchantKey)" }
        var streams: [RecurringStream] = []

        for (key, rows) in groups {
            let sorted = rows.sorted { $0.displayDate < $1.displayDate }
            guard sorted.count >= 2 else { continue }
            let dates = sorted.map { calendar.startOfDay(for: $0.displayDate) }
            let intervals = zip(dates.dropFirst(), dates).map { calendar.dateComponents([.day], from: $1, to: $0).day ?? 0 }
            guard let (cadence, _, minCount) = buckets.first(where: { bucket in
                intervals.allSatisfy { bucket.1.contains($0) } && sorted.count >= bucket.minCount
            }) else { continue }

            let amounts = sorted.map(\.magnitude)
            let median = amounts.sorted()[amounts.count / 2]
            let tolerance = median * Decimal(0.15)
            let stable = amounts.filter { abs($0 - median) <= tolerance }.count
            guard Double(stable) / Double(amounts.count) >= 0.6 else { continue }

            let last = sorted[sorted.count - 1], prev = sorted[sorted.count - 2]
            let lastSeen = dates[dates.count - 1]
            // Roll the expectation forward to the first date after today; two missed periods means it ended.
            var next = cadence.next(after: lastSeen, calendar: calendar)
            let cutoff = cadence.next(after: cadence.next(after: lastSeen, calendar: calendar), calendar: calendar)
            if cutoff < calendar.startOfDay(for: now) { continue }
            while next < calendar.startOfDay(for: now) { next = cadence.next(after: next, calendar: calendar) }

            let kind: StreamKind = last.kind == .income ? .income : streamKind(for: last)
            let previous = prev.magnitude == last.magnitude ? nil : prev.magnitude
            streams.append(RecurringStream(id: key, merchant: last.merchant, kind: kind, cadence: cadence, amount: last.magnitude,
                                           previousAmount: previous, lastSeen: lastSeen, nextExpected: next))
        }
        return streams.sorted { $0.nextExpected < $1.nextExpected }
    }

    /// Bills are the things you can't easily cancel; everything else recurring is a subscription.
    static func streamKind(for t: Transaction) -> StreamKind {
        switch t.category {
        case .home, .health, .transport: .bill
        default: .subscription
        }
    }
}

private func abs(_ d: Decimal) -> Decimal { d < 0 ? -d : d }
