import Foundation

/// The day a charge happened, where the user is. Banks date charges by their own clock — Robinhood by UTC, so a 7:52 pm
/// purchase in Chicago comes dated tomorrow — so the bank's date is the last thing trusted, not the first.
public enum ChargeDay {
    /// - Parameters:
    ///   - authorizedAt: the provider's authorisation time, when it sends a real one. Its day in `calendar` wins.
    ///   - authorized: the bank's authorisation date, then `posted` — calendar days in `calendar` already.
    ///   - seen: when Poise first saw the charge (its pending twin, once posted). It can't have happened on a later day.
    /// - Returns: the start of that day, never after today.
    public static func resolve(authorizedAt: Date?, authorized: Date?, posted: Date, seen: Date?, now: Date = .now, calendar: Calendar = .current) -> Date {
        let today = calendar.startOfDay(for: now)
        let day: Date
        if let authorizedAt {
            day = calendar.startOfDay(for: authorizedAt)
        } else {
            let dated = calendar.startOfDay(for: authorized ?? posted)
            day = seen.map { min(dated, calendar.startOfDay(for: $0)) } ?? dated
        }
        return min(day, today)
    }
}
