import Foundation

/// Finds subscriptions, bills and paychecks from the transaction history — no configuration, no provider add-on.
public enum RecurringDetector {
    /// Cadence buckets in days. A stream needs at least two occurrences (three for weekly) whose intervals land in one bucket
    /// and whose amounts stay within ±15% of the median.
    static let buckets: [(Cadence, ClosedRange<Int>, minCount: Int)] = [
        (.weekly, 5...9, 3), (.biweekly, 12...16, 2), (.monthly, 26...35, 2), (.quarterly, 80...100, 2), (.annual, 350...380, 2),
    ]

    /// A row joins a chain when the gap since the chain's last row fits some cadence and the amount is within this of it.
    static let chainTolerance = Decimal(0.25)

    public static func detect(_ transactions: [Transaction], now: Date, calendar: Calendar = .current, categories: CategorySet = .builtIn) -> [RecurringStream] {
        let eligible = transactions.filter { !$0.pending && ($0.kind == .spend || $0.kind == .income) }
        let groups = Dictionary(grouping: eligible) { "\($0.kind.rawValue)|\($0.merchantKey)" }
        var streams: [RecurringStream] = []

        for (key, rows) in groups {
            // One merchant can carry several rhythms — rent plus its parking line on the same day, two Netflix accounts —
            // so rows are threaded into chains: a row continues the chain whose last row is a cadence away and about the
            // same amount, else starts its own.
            let sorted = rows.sorted { ($0.displayDate, $1.magnitude) < ($1.displayDate, $0.magnitude) }
            var chains: [[Transaction]] = []
            for t in sorted {
                let day = calendar.startOfDay(for: t.displayDate)
                var best: (index: Int, diff: Decimal)?
                for (i, chain) in chains.enumerated() {
                    guard let last = chain.last else { continue }
                    let gap = calendar.dateComponents([.day], from: calendar.startOfDay(for: last.displayDate), to: day).day ?? 0
                    guard buckets.contains(where: { $0.1.contains(gap) }) || semimonthlyGap.contains(gap) else { continue }
                    let diff = abs(t.magnitude - last.magnitude)
                    guard diff <= last.magnitude * chainTolerance else { continue }
                    if best == nil || diff < best!.diff { best = (i, diff) }
                }
                if let best { chains[best.index].append(t) } else { chains.append([t]) }
            }
            // The fullest chain keeps the merchant's plain id; the rest are numbered, so "Not a subscription" sticks to one.
            let ranked = chains.filter { $0.count >= 2 }.sorted { ($0.count, $0.last!.magnitude) > ($1.count, $1.last!.magnitude) }
            for (n, chain) in ranked.enumerated() {
                if let stream = stream(from: chain, id: n == 0 ? key : "\(key)|\(n + 1)", now: now, calendar: calendar, categories: categories) { streams.append(stream) }
            }
        }
        return streams.sorted { $0.nextExpected < $1.nextExpected }
    }

    /// One chain → one stream, when its gaps all fit a single cadence and its amounts hold steady.
    static func stream(from sorted: [Transaction], id: String, now: Date, calendar: Calendar, categories: CategorySet) -> RecurringStream? {
        let dates = sorted.map { calendar.startOfDay(for: $0.displayDate) }
        let intervals = zip(dates.dropFirst(), dates).map { calendar.dateComponents([.day], from: $1, to: $0).day ?? 0 }
        let cadence: Cadence
        if isSemimonthly(dates, intervals: intervals, calendar: calendar) {
            cadence = .semimonthly
        } else if let (c, _, _) = buckets.first(where: { bucket in intervals.allSatisfy { bucket.1.contains($0) } && sorted.count >= bucket.minCount }) {
            cadence = c
        } else { return nil }

        let amounts = sorted.map(\.magnitude)
        let median = amounts.sorted()[amounts.count / 2]
        let tolerance = median * Decimal(0.15)
        let stable = amounts.filter { abs($0 - median) <= tolerance }.count
        guard Double(stable) / Double(amounts.count) >= 0.6 else { return nil }

        let last = sorted[sorted.count - 1], prev = sorted[sorted.count - 2]
        let lastSeen = dates[dates.count - 1]
        // Roll the expectation forward to the first date after today; two missed periods means it ended.
        var next = cadence.next(after: lastSeen, calendar: calendar)
        let cutoff = cadence.next(after: cadence.next(after: lastSeen, calendar: calendar), calendar: calendar)
        if cutoff < calendar.startOfDay(for: now) { return nil }
        var steps = 0
        while next < calendar.startOfDay(for: now), steps < 400 { let n = cadence.next(after: next, calendar: calendar); if n <= next { return nil }; next = n; steps += 1 }

        let kind: StreamKind = last.kind == .income ? .income : streamKind(for: last, categories: categories)
        let previous = prev.magnitude == last.magnitude ? nil : prev.magnitude
        return RecurringStream(id: id, merchant: last.merchant, kind: kind, cadence: cadence, amount: last.magnitude,
                               previousAmount: previous, lastSeen: lastSeen, nextExpected: next, accountID: last.accountID, transactionIDs: sorted.map(\.id))
    }

    /// Paid on the 15th and the last day of the month: gaps of 13–18 days and every date near one of those two marks.
    static let semimonthlyGap = 13...18
    static func isSemimonthly(_ dates: [Date], intervals: [Int], calendar: Calendar) -> Bool {
        guard dates.count >= 2, intervals.allSatisfy({ semimonthlyGap.contains($0) }) else { return false }
        return dates.allSatisfy { d in
            let day = calendar.component(.day, from: d)
            let lastDay = calendar.range(of: .day, in: .month, for: d)?.count ?? 31
            return (12...17).contains(day) || day >= lastDay - 3 || day <= 2
        }
    }

    /// Bills are the things you can't easily cancel (needs); everything else recurring is a subscription.
    static func streamKind(for t: Transaction, categories: CategorySet) -> StreamKind {
        categories.lens(t.categoryID) == .needs ? .bill : .subscription
    }
}

private func abs(_ d: Decimal) -> Decimal { d < 0 ? -d : d }
