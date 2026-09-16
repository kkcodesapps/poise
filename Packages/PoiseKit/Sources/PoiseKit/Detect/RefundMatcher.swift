import Foundation

/// Links a refund to the charge it reverses so the pair nets out instead of showing as income.
public enum RefundMatcher {
    public static func match(_ transactions: [Transaction], window: Int = 90, calendar: Calendar = .current) -> [Transaction] {
        var result = transactions
        for (ri, refund) in result.enumerated() where refund.kind == .refund && refund.pairID == nil {
            let candidates = result.enumerated().filter { (si, s) in
                si != ri && s.kind == .spend && s.pairID == nil && s.merchantKey == refund.merchantKey && s.magnitude >= refund.magnitude
                    && s.displayDate <= refund.displayDate
                    && (calendar.dateComponents([.day], from: s.displayDate, to: refund.displayDate).day ?? 999) <= window
            }
            guard let (si, original) = candidates.max(by: { $0.element.displayDate < $1.element.displayDate }) else { continue }
            result[ri].pairID = original.id
            result[si].pairID = refund.id
        }
        return result
    }
}
