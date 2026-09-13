import Foundation

public enum Cadence: String, Codable, Sendable, CaseIterable {
    case weekly, biweekly, monthly, quarterly, annual

    /// Adds one period to a date.
    public func next(after date: Date, calendar: Calendar) -> Date {
        switch self {
        case .weekly: calendar.date(byAdding: .day, value: 7, to: date) ?? date
        case .biweekly: calendar.date(byAdding: .day, value: 14, to: date) ?? date
        case .monthly: calendar.date(byAdding: .month, value: 1, to: date) ?? date
        case .quarterly: calendar.date(byAdding: .month, value: 3, to: date) ?? date
        case .annual: calendar.date(byAdding: .year, value: 1, to: date) ?? date
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

    public init(id: String, merchant: String, kind: StreamKind, cadence: Cadence, amount: Decimal, previousAmount: Decimal? = nil, lastSeen: Date, nextExpected: Date) {
        self.id = id
        self.merchant = merchant
        self.kind = kind
        self.cadence = cadence
        self.amount = amount
        self.previousAmount = previousAmount
        self.lastSeen = lastSeen
        self.nextExpected = nextExpected
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
        var guardCount = 0
        while d > from, guardCount < 60 { d = cadence.previous(before: d, calendar: calendar); guardCount += 1 }
        while d <= from { d = cadence.next(after: d, calendar: calendar) }
        while d <= through { out.append(d); d = cadence.next(after: d, calendar: calendar) }
        return out
    }
}

extension Cadence {
    func previous(before date: Date, calendar: Calendar) -> Date {
        switch self {
        case .weekly: calendar.date(byAdding: .day, value: -7, to: date) ?? date
        case .biweekly: calendar.date(byAdding: .day, value: -14, to: date) ?? date
        case .monthly: calendar.date(byAdding: .month, value: -1, to: date) ?? date
        case .quarterly: calendar.date(byAdding: .month, value: -3, to: date) ?? date
        case .annual: calendar.date(byAdding: .year, value: -1, to: date) ?? date
        }
    }
}
