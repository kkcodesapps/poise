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
            // A chain that went quiet for two periods and then saw a similar charge is one stream that came back, not two:
            // fold the later rows in and remember when it returned.
            var merged = chains
            var i = 0
            while i < merged.count {
                let chain = merged[i]
                if chain.count >= 2, let probe = stream(from: chain, id: key, now: now, calendar: calendar, categories: categories), let ended = probe.endedAt {
                    if let j = merged.indices.first(where: { $0 != i && merged[$0].first!.displayDate > ended && abs(merged[$0].first!.magnitude - probe.amount) <= probe.amount * chainTolerance }) {
                        let back = merged[j]
                        merged[i] = (chain + back).sorted { ($0.displayDate, $1.magnitude) < ($1.displayDate, $0.magnitude) }
                        merged.remove(at: j)
                        continue   // re-check the merged chain (it may have come back more than once)
                    }
                }
                i += 1
            }
            // The fullest chain keeps the merchant's plain id; the rest are numbered, so "Not a subscription" sticks to one.
            let ranked = merged.filter { $0.count >= 2 }.sorted { ($0.count, $0.last!.magnitude) > ($1.count, $1.last!.magnitude) }
            for (n, chain) in ranked.enumerated() {
                let returnedAt = returnDate(for: chain, calendar: calendar)
                if var stream = stream(from: chain, id: n == 0 ? key : "\(key)|\(n + 1)", now: now, calendar: calendar, categories: categories, returnedAt: returnedAt) {
                    if let r = returnedAt, stream.endedAt == nil { stream.returnedAt = r }
                    streams.append(stream)
                }
            }
        }
        return streams.sorted { $0.nextExpected < $1.nextExpected }
    }

    /// Where a merged chain resumed: the first row after a gap of at least two of its periods.
    static func returnDate(for chain: [Transaction], calendar: Calendar) -> Date? {
        let dates = chain.map { calendar.startOfDay(for: $0.displayDate) }
        let gaps = zip(dates.dropFirst(), dates).map { calendar.dateComponents([.day], from: $1, to: $0).day ?? 0 }
        guard let typical = gaps.filter({ $0 <= 380 }).sorted().first, typical > 0 else { return nil }
        // A gap of more than twice the shortest one is a pause; the row after the last pause is the return.
        for (k, g) in gaps.enumerated().reversed() where g > typical * 2 + 3 { return dates[k + 1] }
        return nil
    }

    /// One chain → one stream, when its gaps all fit a single cadence and its amounts hold steady. A chain that resumed
    /// after a pause is judged on its regular gaps; a stream two periods overdue is kept, marked ended, rather than dropped.
    static func stream(from sorted: [Transaction], id: String, now: Date, calendar: Calendar, categories: CategorySet, returnedAt: Date? = nil) -> RecurringStream? {
        let dates = sorted.map { calendar.startOfDay(for: $0.displayDate) }
        let allIntervals = zip(dates.dropFirst(), dates).map { calendar.dateComponents([.day], from: $1, to: $0).day ?? 0 }
        let intervals = returnedAt == nil ? allIntervals : allIntervals.filter { $0 <= 380 && $0 <= (allIntervals.filter { $0 <= 380 }.min() ?? 0) * 2 + 3 }
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
        let today = calendar.startOfDay(for: now)
        // Roll the expectation forward to the first date after today. Two missed periods (a yearly: one, plus 60 days)
        // means it ended — it stays, marked with the first date it didn't come, so it can be shown and watched.
        var next = cadence.next(after: lastSeen, calendar: calendar)
        let firstMissed = next
        let cutoff = cadence == .annual ? (calendar.date(byAdding: .day, value: 60, to: next) ?? next) : cadence.next(after: next, calendar: calendar)
        var endedAt: Date?
        if cutoff < today { endedAt = firstMissed }
        else {
            var steps = 0
            while next < today, steps < 400 { let n = cadence.next(after: next, calendar: calendar); if n <= next { return nil }; next = n; steps += 1 }
        }

        let kind: StreamKind = last.kind == .income ? .income : streamKind(for: last, categories: categories)
        let previous = prev.magnitude == last.magnitude ? nil : prev.magnitude
        return RecurringStream(id: id, merchant: last.merchant, kind: kind, cadence: cadence, amount: last.magnitude,
                               previousAmount: previous, lastSeen: lastSeen, nextExpected: next, accountID: last.accountID, transactionIDs: sorted.map(\.id), endedAt: endedAt)
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
