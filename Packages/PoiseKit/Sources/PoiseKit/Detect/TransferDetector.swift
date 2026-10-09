import Foundation

/// Pairs money that moved between the user's own accounts so it is never counted as spending.
public enum TransferDetector {
    /// An outflow and an inflow of equal size on two different accounts within `window` days become a pair.
    /// If the receiving account is a credit card the pair is a card payment; otherwise a transfer.
    /// Already-paired rows are left alone. Order is preserved.
    public static func pair(_ transactions: [Transaction], accounts: [Account], window: Int = 3, calendar: Calendar = .current) -> [Transaction] {
        let roles = Dictionary(uniqueKeysWithValues: accounts.map { ($0.id, $0.role) })
        var result = transactions
        // One day index per row; a year of rows would otherwise mean millions of Calendar calls.
        let epoch = calendar.startOfDay(for: Date(timeIntervalSinceReferenceDate: 0))
        let day = result.map { calendar.dateComponents([.day], from: epoch, to: calendar.startOfDay(for: $0.date)).day ?? 0 }
        var inflowsByAmount: [Decimal: [Int]] = [:]
        for (i, t) in result.enumerated() where !t.isOutflow && t.pairID == nil && t.kind != .refund { inflowsByAmount[t.magnitude, default: []].append(i) }

        let outflows = result.indices
            .filter { result[$0].isOutflow && result[$0].pairID == nil && result[$0].kind != .refund }
            .sorted { result[$0].date < result[$1].date }

        for oi in outflows {
            guard result[oi].pairID == nil else { continue }
            let out = result[oi]
            let best = (inflowsByAmount[out.magnitude] ?? [])
                .filter { ii in result[ii].pairID == nil && result[ii].accountID != out.accountID && abs(day[ii] - day[oi]) <= window }
                .min { abs(day[$0] - day[oi]) < abs(day[$1] - day[oi]) }
            guard let ii = best else { continue }
            let kind: TransactionKind = roles[result[ii].accountID] == .credit ? .ccPayment : .transfer
            let inID = result[ii].id
            result[oi].kind = kind; result[oi].pairID = inID
            result[ii].kind = kind; result[ii].pairID = out.id
        }
        return result
    }

    static func days(from a: Date, to b: Date, calendar: Calendar) -> Int {
        calendar.dateComponents([.day], from: calendar.startOfDay(for: a), to: calendar.startOfDay(for: b)).day ?? 0
    }
}
