import Foundation

/// What a transaction *is*. Category says what it was *for*; kind decides how the math treats it.
public enum TransactionKind: String, Codable, Sendable, CaseIterable {
    case spend
    case income
    /// Between the user's own accounts. Never spend; into savings counts as kept.
    case transfer
    /// Paying a credit card from a spending account. Ignored — the spend was counted at swipe.
    case ccPayment = "cc_payment"
    /// Inflow matched to an earlier spend at the same merchant. Nets against it.
    case refund
    /// ATM cash, peer-to-peer apps with no context. Counted as spend, flagged for tagging.
    case untracked
}

public struct Transaction: Identifiable, Hashable, Codable, Sendable {
    public let id: String
    public var accountID: String
    /// Signed: negative is money out, positive is money in.
    public var amount: Decimal
    public var merchant: String
    /// When the card was actually used, if the provider reports it.
    public var authorizedDate: Date?
    /// The provider's date (posting date, or expected posting date while pending).
    public var date: Date
    public var pending: Bool
    public var kind: TransactionKind
    public var category: SpendCategory?
    /// The other side of a transfer or card payment, or the charge a refund nets against.
    public var pairID: String?
    /// Bank / ATM / foreign-transaction / interest charges, as reported by the provider.
    public var isFee: Bool

    public init(id: String, accountID: String, amount: Decimal, merchant: String, authorizedDate: Date? = nil, date: Date, pending: Bool = false, kind: TransactionKind = .spend, category: SpendCategory? = nil, pairID: String? = nil, isFee: Bool = false) {
        self.id = id
        self.accountID = accountID
        self.amount = amount
        self.merchant = merchant
        self.authorizedDate = authorizedDate
        self.date = date
        self.pending = pending
        self.kind = kind
        self.category = category
        self.pairID = pairID
        self.isFee = isFee
    }

    /// The day the user actually paid: authorized when known, else the provider's date.
    public var displayDate: Date { authorizedDate ?? date }
    public var isOutflow: Bool { amount < 0 }
    public var magnitude: Decimal { amount < 0 ? -amount : amount }

    /// Normalized merchant key used for grouping and rules: lower-case letters and spaces only.
    public var merchantKey: String { Transaction.merchantKey(merchant) }

    public static func merchantKey(_ name: String) -> String {
        let lowered = name.lowercased()
        let cleaned = lowered.map { $0.isLetter || $0 == " " ? $0 : " " }
        return String(cleaned).split(separator: " ").joined(separator: " ")
    }
}
