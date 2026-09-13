import Foundation

public enum VerdictStatus: String, Codable, Sendable {
    case goodShape, onTrack, headsUp
}

/// The first day the spending balance goes negative before payday, and by how much.
public struct Crunch: Hashable, Sendable {
    public let date: Date
    public let shortfall: Decimal
}

/// Where you stand against everything due before the next payday.
public struct Ahead: Hashable, Sendable {
    /// Spending balances minus bills due in the window minus committed savings.
    public let amount: Decimal
    public let through: Date
    public let crunch: Crunch?
}

/// What stayed with you this month: income − net spend, and where that lands at month-end.
/// Transfers into savings are not spend, so they are already kept — adding them again would double count.
public struct Kept: Hashable, Sendable {
    public let keptSoFar: Decimal
    public let expectedIncome: Decimal
    /// Projected kept ÷ expected income for the month. Uses expected income so early-month never reads negative.
    public let onPacePercent: Double
}

public struct Verdict: Hashable, Sendable {
    public let status: VerdictStatus
    public let ahead: Ahead
    public let kept: Kept

    /// The status line. Positive at every size; when it's bad it's an instruction.
    public var sentence: String {
        switch status {
        case .goodShape: return "You’re in good shape."
        case .onTrack: return "On track."
        case .headsUp:
            if let crunch = ahead.crunch {
                let day = crunch.date.formatted(.dateTime.day(.ordinalOfDayInMonth))
                return "Heads up — checking runs short on the \(day)."
            }
            return "Heads up."
        }
    }
}

public struct VerdictInput: Sendable {
    public var accounts: [Account]
    public var transactions: [Transaction]
    public var streams: [RecurringStream]
    public var now: Date
    /// Explicit payday. When nil, derived from the income stream, else 14 days out.
    public var nextPayday: Date?
    /// Expected income for the month. When nil, derived from the income stream, else income so far.
    public var expectedIncome: Decimal?
    /// Kept-pace target. Default until there is a last month to beat.
    public var keptTarget: Double
    public var committedSavings: Decimal
    /// Unacknowledged duplicates, fees, price changes. Any of them is a heads-up.
    public var anomalies: Int
    public var calendar: Calendar

    public init(accounts: [Account], transactions: [Transaction], streams: [RecurringStream], now: Date, nextPayday: Date? = nil, expectedIncome: Decimal? = nil, keptTarget: Double = 0.20, committedSavings: Decimal = 0, anomalies: Int = 0, calendar: Calendar = .current) {
        self.accounts = accounts
        self.transactions = transactions
        self.streams = streams
        self.now = now
        self.nextPayday = nextPayday
        self.expectedIncome = expectedIncome
        self.keptTarget = keptTarget
        self.committedSavings = committedSavings
        self.anomalies = anomalies
        self.calendar = calendar
    }
}

public enum VerdictEngine {
    public static func verdict(for input: VerdictInput) -> Verdict {
        let ahead = ahead(input)
        let kept = kept(input)
        return Verdict(status: status(ahead: ahead, kept: kept, target: input.keptTarget, anomalies: input.anomalies), ahead: ahead, kept: kept)
    }

    public static func status(ahead: Ahead, kept: Kept, target: Double, anomalies: Int) -> VerdictStatus {
        if ahead.crunch != nil || kept.onPacePercent < 0 || anomalies > 0 { return .headsUp }
        if ahead.amount >= 0, kept.onPacePercent >= target { return .goodShape }
        return .onTrack
    }

    /// Next payday: explicit, else the income stream's next occurrence, else two weeks out.
    public static func nextPayday(_ input: VerdictInput) -> Date {
        if let d = input.nextPayday { return d }
        let cal = input.calendar
        if let income = input.streams.filter({ $0.kind == .income }).max(by: { $0.amount < $1.amount }) {
            if let d = income.occurrences(after: input.now, through: cal.date(byAdding: .day, value: 400, to: input.now) ?? input.now, calendar: cal).first { return d }
        }
        return cal.date(byAdding: .day, value: 14, to: input.now) ?? input.now
    }

    /// Walks each day from tomorrow through payday, applying expected outflows (and any income that lands before payday).
    public static func ahead(_ input: VerdictInput) -> Ahead {
        let cal = input.calendar
        let payday = cal.startOfDay(for: nextPayday(input))
        let today = cal.startOfDay(for: input.now)
        var balance = input.accounts.filter { $0.role == .spending }.reduce(Decimal(0)) { $0 + $1.balance }

        var byDay: [Date: Decimal] = [:]
        for s in input.streams {
            for d in s.occurrences(after: today, through: payday, calendar: cal) {
                let day = cal.startOfDay(for: d)
                if s.kind == .income {
                    if day < payday { byDay[day, default: 0] += s.amount }   // payday itself is the boundary, not counted
                } else {
                    byDay[day, default: 0] -= s.amount
                }
            }
        }

        var crunch: Crunch?
        var day = cal.date(byAdding: .day, value: 1, to: today) ?? today
        while day <= payday {
            balance += byDay[day] ?? 0
            if balance < 0, crunch == nil { crunch = Crunch(date: day, shortfall: -balance) }
            day = cal.date(byAdding: .day, value: 1, to: day) ?? payday.addingTimeInterval(1)
        }
        return Ahead(amount: balance - input.committedSavings, through: payday, crunch: crunch)
    }

    public static func kept(_ input: VerdictInput) -> Kept {
        let cal = input.calendar
        guard let month = cal.dateInterval(of: .month, for: input.now) else {
            return Kept(keptSoFar: 0, expectedIncome: 0, onPacePercent: 0)
        }
        let inMonth = input.transactions.filter { month.contains($0.displayDate) && $0.displayDate <= input.now }

        var income: Decimal = 0, spend: Decimal = 0, wants: Decimal = 0, refunds: Decimal = 0
        for t in inMonth {
            switch t.kind {
            case .income: income += t.amount
            case .spend, .untracked:
                spend += t.magnitude
                if (t.category?.lens ?? .wants) == .wants { wants += t.magnitude }
            case .refund: refunds += t.amount
            case .transfer, .ccPayment: break
            }
        }
        let netSpend = spend - refunds
        let keptSoFar = income - netSpend

        let expected: Decimal = input.expectedIncome ?? {
            let fromStreams = input.streams.filter { $0.kind == .income }.reduce(Decimal(0)) { acc, s in
                acc + s.amount * Decimal(s.occurrences(after: month.start.addingTimeInterval(-1), through: month.end.addingTimeInterval(-1), calendar: cal).count)
            }
            return fromStreams > 0 ? fromStreams : income
        }()

        let dayOfMonth = max(1, cal.component(.day, from: input.now))
        let daysInMonth = cal.range(of: .day, in: .month, for: input.now)?.count ?? 30
        let daysRemaining = Decimal(max(0, daysInMonth - dayOfMonth))
        let avgDailyWants = wants / Decimal(dayOfMonth)
        let billsRemaining = input.streams.filter { $0.kind != .income }.reduce(Decimal(0)) { acc, s in
            acc + s.amount * Decimal(s.occurrences(after: input.now, through: month.end.addingTimeInterval(-1), calendar: cal).count)
        }
        let projectedSpend = netSpend + avgDailyWants * daysRemaining + billsRemaining
        let projectedKept = expected - projectedSpend
        let onPace = expected > 0 ? Double(truncating: (projectedKept / expected) as NSDecimalNumber) : 0
        return Kept(keptSoFar: keptSoFar, expectedIncome: expected, onPacePercent: onPace)
    }
}
