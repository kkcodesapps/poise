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
    /// A card's next statement: when it's due, what's owed on it, and the least that keeps it current.
    public var statementDue: Date?
    public var statementAmount: Decimal?
    public var minimumDue: Decimal?
    /// True when `statementAmount` was rebuilt from the rows rather than reported by the provider.
    public var statementIsEstimate = false

    public init(id: String, name: String, mask: String? = nil, role: AccountRole, available: Decimal? = nil, current: Decimal, currency: String = "USD",
                institution: String? = nil, itemID: String? = nil, hidden: Bool = false, hiddenAt: Date? = nil, balanceAt: Date? = nil,
                statementDue: Date? = nil, statementAmount: Decimal? = nil, minimumDue: Decimal? = nil) {
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
    }

    /// What leaves checking on the due date: the whole statement when paid in full, else the minimum. Nil when nothing is known.
    public func statementPayment(paysInFull: Bool) -> Decimal? {
        guard role == .credit, statementDue != nil else { return nil }
        let amount = paysInFull ? (statementAmount ?? minimumDue) : (minimumDue ?? statementAmount)
        guard let amount, amount > 0 else { return nil }
        return amount
    }

    /// What the math uses: available if the provider reports it, else current.
    public var balance: Decimal { available ?? current }
}
