import Foundation

/// What an account is *for*. Drives which balances count toward Ahead and how transfers into it are treated.
public enum AccountRole: String, Codable, Sendable, CaseIterable {
    /// Checking / cash-management. Balances count toward Ahead; spend and income here count toward Kept.
    case spending
    /// Transfers into a savings account count as kept, never as spend.
    case savings
    /// Spend is counted at swipe time; payments to the card are not spend.
    case credit
    /// Investments, loans, anything else. Shown, ignored by the math.
    case other
}

/// How a card gets paid each month — which decides what the forecast subtracts on the due date.
///
/// The statement balance and the whole balance are different sums whenever the card has been used since the statement
/// closed, and on a busy card they're thousands apart. Paying the statement is the one that avoids interest, so it's
/// what a default should be.
public enum CardPayment: String, Codable, Sendable, CaseIterable {
    case statement, full, minimum, fixed

    public var title: String {
        switch self {
        case .statement: "The statement balance"
        case .full: "The whole balance"
        case .minimum: "The minimum"
        case .fixed: "Something else"
        }
    }

    public var detail: String {
        switch self {
        case .statement: "What was owed when it closed — no interest"
        case .full: "Clears the card, this month's charges too"
        case .minimum: "Only what keeps it current"
        case .fixed: "A set amount each month"
        }
    }

    /// How Settings names it as a default, where there's no card in front of the user.
    public var shortTitle: String {
        switch self {
        case .statement: "Statement balance"
        case .full: "Whole balance"
        case .minimum: "Minimum"
        case .fixed: "A set amount"
        }
    }
}

public struct Account: Identifiable, Hashable, Codable, Sendable {
    public let id: String
    public var name: String
    public var mask: String?
    public var role: AccountRole
    /// The provider's available balance, when it gives one.
    public var available: Decimal?
    public var current: Decimal
    public var currency: String
    /// Where it lives ("Chase", "Apple") and the connection it came through.
    public var institution: String?
    public var itemID: String?
    /// Taken out of the math by the user. The engine never sees hidden accounts; the app keeps them aside.
    public var hidden: Bool
    public var hiddenAt: Date?
    /// When the provider last reported the balance.
    public var balanceAt: Date?
    /// How this card is paid, when the user has said. Nil follows whatever Settings says new cards do, so changing
    /// the default still moves every card the user hasn't decided about.
    public var pays: CardPayment?
    /// The amount for `.fixed`.
    public var paysFixedAmount: Decimal?
    /// A card's next statement: when it's due, what's owed on it, and the least that keeps it current.
    public var statementDue: Date?
    public var statementAmount: Decimal?
    public var minimumDue: Decimal?
    /// True when `statementAmount` was rebuilt from the rows rather than reported by the provider.
    public var statementIsEstimate = false
    /// The user's own name for it; `name` already carries it when set. `bankName` is what the bank calls it, without
    /// the ® and ™ the bank adds.
    public var nickname: String?
    public var bankName: String?
    /// The finish picked for its card art, by raw value. Nil means the one Poise chooses for the issuer.
    public var finish: String?
    /// The chip's metal, by raw value. Nil means the one that comes with the finish.
    public var chip: String?

    public init(id: String, name: String, mask: String? = nil, role: AccountRole, available: Decimal? = nil, current: Decimal, currency: String = "USD",
                institution: String? = nil, itemID: String? = nil, hidden: Bool = false, hiddenAt: Date? = nil, balanceAt: Date? = nil,
                statementDue: Date? = nil, statementAmount: Decimal? = nil, minimumDue: Decimal? = nil,
                pays: CardPayment? = nil, paysFixedAmount: Decimal? = nil) {
        self.id = id
        self.name = name
        self.mask = mask
        self.role = role
        self.available = available
        self.current = current
        self.currency = currency
        self.institution = institution
        self.itemID = itemID
        self.hidden = hidden
        self.hiddenAt = hiddenAt
        self.balanceAt = balanceAt
        self.statementDue = statementDue
        self.statementAmount = statementAmount
        self.minimumDue = minimumDue
        self.pays = pays
        self.paysFixedAmount = paysFixedAmount
    }

    /// What's owed on the card right now.
    ///
    /// Deliberately `current`, never `available`: on a credit card `available` is the credit left to spend, so a card
    /// owing $1,284 against a $12,000 limit reports $10,715 available — and offering to pay *that* off is nonsense.
    /// Providers also disagree on the sign of what's owed, so the size of it is the part that means anything.
    public var owed: Decimal { role == .credit ? (current < 0 ? -current : current) : balance }

    /// What leaves checking on the due date. `default` is what Settings says new cards do, used for any card the user
    /// hasn't decided about. Nil when nothing is known, or when the choice has no figure behind it.
    public func statementPayment(default fallback: CardPayment = .statement) -> Decimal? {
        guard role == .credit, statementDue != nil else { return nil }
        let amount: Decimal?
        switch pays ?? fallback {
        case .statement: amount = statementAmount ?? minimumDue
        case .full: amount = owed
        case .minimum: amount = minimumDue ?? statementAmount
        case .fixed: amount = paysFixedAmount
        }
        guard let amount, amount > 0 else { return nil }
        return amount
    }

    /// When this card's payment is actually next due.
    ///
    /// A provider's due date goes stale. It keeps reporting last month's date until the next statement closes, so for
    /// the days in between a card looks like it has nothing due — and its payment vanished from the forecast entirely
    /// rather than showing up a few weeks out. Rolling the date forward whole months keeps it visible on roughly the
    /// right day, which is far closer to the truth than leaving thousands of dollars out.
    public func nextDue(now: Date, calendar: Calendar = .current) -> (date: Date, isEstimate: Bool)? {
        guard role == .credit, let due = statementDue else { return nil }
        let today = calendar.startOfDay(for: now)
        if calendar.startOfDay(for: due) > today { return (due, false) }
        var rolled = due
        // Months, not 30 days: a card falls due on the same date each month.
        while calendar.startOfDay(for: rolled) <= today {
            guard let next = calendar.date(byAdding: .month, value: 1, to: rolled) else { return nil }
            rolled = next
        }
        return (rolled, true)
    }

    /// What the math uses: available if the provider reports it, else current.
    public var balance: Decimal { available ?? current }
}
