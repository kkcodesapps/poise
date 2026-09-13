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

    public init(id: String, name: String, mask: String? = nil, role: AccountRole, available: Decimal? = nil, current: Decimal, currency: String = "USD") {
        self.id = id
        self.name = name
        self.mask = mask
        self.role = role
        self.available = available
        self.current = current
        self.currency = currency
    }

    /// What the math uses: available if the provider reports it, else current.
    public var balance: Decimal { available ?? current }
}
