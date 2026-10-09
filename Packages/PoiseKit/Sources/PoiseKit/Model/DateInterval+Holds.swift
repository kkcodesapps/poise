import Foundation

public extension DateInterval {
    /// Half-open membership: `start ≤ date < end`. `DateInterval.contains` includes the end instant, and every
    /// provider row is dated at local midnight — so a charge on the 1st would count in both months, and a Friday
    /// charge in both Thursday and Friday. Use this for anything bucketed by day, week, month or year.
    func holds(_ date: Date) -> Bool { date >= start && date < end }
}
