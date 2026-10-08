import Foundation

/// Links a refund to the charge it reverses so the pair nets out instead of showing as income.
public enum RefundMatcher {
    public static func match(_ transactions: [Transaction], window: Int = 90, calendar: Calendar = .current) -> [Transaction] {
        var result = transactions
        var chargesByMerchant: [String: [Int]] = [:]
        for (i, t) in result.enumerated() where t.kind == .spend && t.pairID == nil { chargesByMerchant[t.merchantKey, default: []].append(i) }
        for ri in result.indices where result[ri].kind == .refund && result[ri].pairID == nil {
            let refund = result[ri]
            let candidates = (chargesByMerchant[refund.merchantKey] ?? []).filter { si in
                let s = result[si]
                return si != ri && s.pairID == nil && s.magnitude >= refund.magnitude && s.displayDate <= refund.displayDate
                    && (calendar.dateComponents([.day], from: s.displayDate, to: refund.displayDate).day ?? 999) <= window
            }
            guard let si = candidates.max(by: { result[$0].displayDate < result[$1].displayDate }) else { continue }
            result[ri].pairID = result[si].id
            result[si].pairID = refund.id
        }
        return result
    }
}
