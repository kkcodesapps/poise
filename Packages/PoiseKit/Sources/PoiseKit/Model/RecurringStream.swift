import Foundation

public enum Cadence: String, Codable, Sendable, CaseIterable {
    case weekly, biweekly, semimonthly, monthly, quarterly, annual

    /// Adds one period to a date. Semi-monthly means the 15th and the last day of the month — a paycheck rhythm — and
    /// lands on the Friday before when that falls on a weekend, as payroll does.
    public func next(after date: Date, calendar: Calendar) -> Date {
        switch self {
        case .weekly: return calendar.date(byAdding: .day, value: 7, to: date) ?? date
        case .biweekly: return calendar.date(byAdding: .day, value: 14, to: date) ?? date
        case .semimonthly:
            // The anchors come from the calendar, never from the (weekend-shifted) date, so this always moves forward.
            return Cadence.semimonthlyAnchors(around: date, calendar: calendar).first { $0 > date } ?? (calendar.date(byAdding: .day, value: 15, to: date) ?? date)
        case .monthly: return calendar.date(byAdding: .month, value: 1, to: date) ?? date
        case .quarterly: return calendar.date(byAdding: .month, value: 3, to: date) ?? date
        case .annual: return calendar.date(byAdding: .year, value: 1, to: date) ?? date
        }
    }

    /// The 15th and last day of the month before, of, and after `date`, each pulled to the Friday before a weekend, in order.
    static func semimonthlyAnchors(around date: Date, calendar: Calendar) -> [Date] {
        (-1...1).flatMap { m -> [Date] in
            let month = calendar.date(byAdding: .month, value: m, to: date) ?? date
            return [dayOfMonth(15, in: month, calendar: calendar), endOfMonth(of: month, calendar: calendar)].map { beforeWeekend($0, calendar: calendar) }
        }.sorted()
    }

    public static func dayOfMonth(_ day: Int, in date: Date, calendar: Calendar) -> Date {
        var c = calendar.dateComponents([.year, .month], from: date); c.day = day
        return calendar.date(from: c) ?? date
    }
    public static func endOfMonth(of date: Date, calendar: Calendar) -> Date {
        guard let month = calendar.dateInterval(of: .month, for: date) else { return date }
        return calendar.date(byAdding: .day, value: -1, to: month.end) ?? date
    }
    public static func beforeWeekend(_ date: Date, calendar: Calendar) -> Date {
        switch calendar.component(.weekday, from: date) {
        case 1: return calendar.date(byAdding: .day, value: -2, to: date) ?? date   // Sunday → Friday
        case 7: return calendar.date(byAdding: .day, value: -1, to: date) ?? date   // Saturday → Friday
        default: return date
        }
    }
}

public enum StreamKind: String, Codable, Sendable, CaseIterable {
    case subscription, bill, income
}

/// A detected recurring stream: a subscription, a bill, or a paycheck.
public struct RecurringStream: Identifiable, Hashable, Codable, Sendable {
    public let id: String
    public var merchant: String
    public var kind: StreamKind
    public var cadence: Cadence
    /// Magnitude of the last occurrence.
    public var amount: Decimal
    /// Magnitude of the occurrence before that, when there is one. `amount > previousAmount` is price creep.
    public var previousAmount: Decimal?
    public var lastSeen: Date
    public var nextExpected: Date
    /// Where the last occurrence landed — a card's subscriptions settle through its statement, not checking.
    public var accountID: String?
    /// The rows behind the stream, newest last.
    public var transactionIDs: [String]

    public init(id: String, merchant: String, kind: StreamKind, cadence: Cadence, amount: Decimal, previousAmount: Decimal? = nil, lastSeen: Date, nextExpected: Date,
                accountID: String? = nil, transactionIDs: [String] = []) {
        self.id = id
        self.merchant = merchant
        self.kind = kind
        self.cadence = cadence
        self.amount = amount
        self.previousAmount = previousAmount
        self.lastSeen = lastSeen
        self.nextExpected = nextExpected
        self.accountID = accountID
        self.transactionIDs = transactionIDs
    }

    public var priceWentUp: Bool {
        guard let previousAmount else { return false }
        return amount > previousAmount
    }

    /// Every expected occurrence in `(from, through]`.
    public func occurrences(after from: Date, through: Date, calendar: Calendar) -> [Date] {
        var out: [Date] = []
        var d = nextExpected
        // Walk back if nextExpected is stale, forward until past the window.
        // Every walk is capped: a cadence that ever failed to advance must not hang the app.
        var guardCount = 0
        while d > from, guardCount < 60 { d = cadence.previous(before: d, calendar: calendar); guardCount += 1 }
        guardCount = 0
        while d <= from, guardCount < 400 { let n = cadence.next(after: d, calendar: calendar); if n <= d { return out }; d = n; guardCount += 1 }
        guardCount = 0
        while d <= through, guardCount < 400 { out.append(d); let n = cadence.next(after: d, calendar: calendar); if n <= d { break }; d = n; guardCount += 1 }
        return out
    }
}

extension Cadence {
    func previous(before date: Date, calendar: Calendar) -> Date {
        switch self {
        case .weekly: return calendar.date(byAdding: .day, value: -7, to: date) ?? date
        case .biweekly: return calendar.date(byAdding: .day, value: -14, to: date) ?? date
        case .semimonthly:
            return Cadence.semimonthlyAnchors(around: date, calendar: calendar).last { $0 < date } ?? (calendar.date(byAdding: .day, value: -15, to: date) ?? date)
        case .monthly: return calendar.date(byAdding: .month, value: -1, to: date) ?? date
        case .quarterly: return calendar.date(byAdding: .month, value: -3, to: date) ?? date
        case .annual: return calendar.date(byAdding: .year, value: -1, to: date) ?? date
        }
    }
}
