import Foundation

/// Pairs money that moved between the user's own accounts so it is never counted as spending.
public enum TransferDetector {
    /// An outflow and an inflow of equal size on two different accounts within `window` days become a pair.
    /// If the receiving account is a credit card the pair is a card payment; otherwise a transfer.
    /// Already-paired rows are left alone. Order is preserved.
    public static func pair(_ transactions: [Transaction], accounts: [Account], window: Int = 3, calendar: Calendar = .current) -> [Transaction] {
        let roles = Dictionary(uniqueKeysWithValues: accounts.map { ($0.id, $0.role) })
        var result = transactions
        var indexByID = [String: Int]()
        for (i, t) in result.enumerated() { indexByID[t.id] = i }

        let outflows = result.enumerated()
            .filter { $0.element.isOutflow && $0.element.pairID == nil && $0.element.kind != .refund }
            .sorted { $0.element.date < $1.element.date }

        for (oi, out) in outflows {
            guard result[oi].pairID == nil else { continue }
            let candidates = result.enumerated().filter { (ii, inn) in
                !inn.isOutflow && inn.pairID == nil && inn.accountID != out.accountID && inn.magnitude == out.magnitude && inn.kind != .refund
                    && abs(days(from: out.date, to: inn.date, calendar: calendar)) <= window && ii != oi
            }
            guard let (ii, inn) = candidates.min(by: { abs(days(from: out.date, to: $0.element.date, calendar: calendar)) < abs(days(from: out.date, to: $1.element.date, calendar: calendar)) }) else { continue }
            let kind: TransactionKind = roles[inn.accountID] == .credit ? .ccPayment : .transfer
            result[oi].kind = kind; result[oi].pairID = inn.id
            result[ii].kind = kind; result[ii].pairID = out.id
        }
        return result
    }

    static func days(from a: Date, to b: Date, calendar: Calendar) -> Int {
        calendar.dateComponents([.day], from: calendar.startOfDay(for: a), to: calendar.startOfDay(for: b)).day ?? 0
    }
}
