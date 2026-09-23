import Foundation

public enum Period: String, CaseIterable, Sendable, Codable {
    case week, month, year
    public var title: String { switch self { case .week: "Week"; case .month: "Month"; case .year: "Year" } }
}

/// One bar of the period strip: a day in a week, a week in a month, a month in a year.
public struct Slice: Hashable, Sendable, Identifiable {
    public let interval: DateInterval
    public let label: String
    public let longLabel: String
    public var id: Date { interval.start }
}

/// Week / month / year windows, Monday-first, and how each splits into slices.
public enum Periods {
    static func mondayCalendar(_ calendar: Calendar) -> Calendar { var c = calendar; c.firstWeekday = 2; return c }
    /// Formats in the calendar's own time zone, so a window's title never drifts a day when the device zone differs.
    static func style(_ calendar: Calendar) -> Date.FormatStyle { Date.FormatStyle(calendar: calendar, timeZone: calendar.timeZone) }

    public static func window(_ period: Period, containing date: Date, calendar: Calendar = .current) -> DateInterval {
        let cal = mondayCalendar(calendar)
        switch period {
        case .week: return cal.dateInterval(of: .weekOfYear, for: date)!
        case .month: return cal.dateInterval(of: .month, for: date)!
        case .year: return cal.dateInterval(of: .year, for: date)!
        }
    }

    public static func shift(_ window: DateInterval, _ period: Period, by n: Int, calendar: Calendar = .current) -> DateInterval {
        let cal = mondayCalendar(calendar)
        let component: Calendar.Component = period == .week ? .weekOfYear : period == .month ? .month : .year
        let d = cal.date(byAdding: component, value: n, to: window.start)!
        return self.window(period, containing: d, calendar: cal)
    }

    /// The previous window, cut to the same elapsed length when the current one is still in progress
    /// (September 1–15 compares to August 1–15; a finished month compares to the whole previous month).
    public static func comparable(previousOf window: DateInterval, _ period: Period, now: Date, calendar: Calendar = .current) -> DateInterval {
        let prev = shift(window, period, by: -1, calendar: calendar)
        guard window.contains(now) else { return prev }
        let elapsed = now.timeIntervalSince(window.start)
        return DateInterval(start: prev.start, end: min(prev.end, prev.start.addingTimeInterval(elapsed)))
    }

    public static func slices(_ window: DateInterval, _ period: Period, calendar: Calendar = .current) -> [Slice] {
        let cal = mondayCalendar(calendar)
        var out: [Slice] = []
        switch period {
        case .week:
            var d = window.start
            while d < window.end {
                let next = cal.date(byAdding: .day, value: 1, to: d)!
                out.append(Slice(interval: DateInterval(start: d, end: next), label: d.formatted(style(cal).weekday(.abbreviated)), longLabel: d.formatted(style(cal).weekday(.wide).month(.abbreviated).day())))
                d = next
            }
        case .month:
            var d = window.start
            while d < window.end {
                let next = min(cal.date(byAdding: .day, value: 7, to: d)!, window.end)
                let a = cal.component(.day, from: d), b = cal.component(.day, from: next.addingTimeInterval(-1))
                out.append(Slice(interval: DateInterval(start: d, end: next), label: a == b ? "\(a)" : "\(a)–\(b)", longLabel: "\(d.formatted(style(cal).month(.abbreviated))) \(a) – \(b)"))
                d = next
            }
        case .year:
            var d = window.start
            while d < window.end {
                let next = cal.date(byAdding: .month, value: 1, to: d)!
                out.append(Slice(interval: DateInterval(start: d, end: next), label: String(d.formatted(style(cal).month(.abbreviated)).prefix(1)), longLabel: d.formatted(style(cal).month(.wide))))
                d = next
            }
        }
        return out
    }

    public static func title(_ window: DateInterval, _ period: Period, calendar: Calendar = .current) -> String {
        let last = window.end.addingTimeInterval(-1), f = style(calendar)
        switch period {
        case .week: return "\(window.start.formatted(f.month(.abbreviated).day())) – \(last.formatted(f.month(.abbreviated).day()))"
        case .month: return window.start.formatted(f.month(.wide))
        case .year: return window.start.formatted(f.year())
        }
    }

    public static func previousLabel(_ period: Period) -> String { switch period { case .week: "last week"; case .month: "last month"; case .year: "last year" } }

    /// Compact "vs" label for rows: "vs Aug", "vs last wk", "vs 2025".
    public static func shortPreviousLabel(_ window: DateInterval, _ period: Period, calendar: Calendar = .current) -> String {
        let prev = shift(window, period, by: -1, calendar: calendar)
        switch period {
        case .week: return "vs last wk"
        case .month: return "vs \(prev.start.formatted(style(calendar).month(.abbreviated)))"
        case .year: return "vs \(prev.start.formatted(style(calendar).year()))"
        }
    }
}
