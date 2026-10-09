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
    public var merchant: String { didSet { merchantKey = Transaction.merchantKey(merchant) } }
    /// Lower-cased letters only — the identity of a merchant across descriptors. Cached; every detector groups by it.
    public private(set) var merchantKey: String
    /// When the card was actually used, if the provider reports it.
    public var authorizedDate: Date?
    /// The provider's date (posting date, or expected posting date while pending).
    public var date: Date
    public var pending: Bool
    public var kind: TransactionKind
    /// Category id: a built-in's raw value ("dining") or a custom category's UUID. See `CategorySet`.
    public var categoryID: String?
    /// The other side of a transfer or card payment, or the charge a refund nets against.
    public var pairID: String?
    /// Bank / ATM / foreign-transaction / interest charges, as reported by the provider.
    public var isFee: Bool
    /// The user's name for it — per charge, or from a merchant rule. `merchant` stays the bank's descriptor.
    public var displayName: String?
    public var note: String?
    /// Left out of the math by the user. Still in the feed; never in Kept, Pace, Where, streams or anomalies.
    public var excluded: Bool
    /// When the row first reached the server — what "since you last looked" is measured against.
    public var createdAt: Date?
    /// The merchant's logo, when the provider has one.
    public var logoURL: String?

    public init(id: String, accountID: String, amount: Decimal, merchant: String, authorizedDate: Date? = nil, date: Date, pending: Bool = false, kind: TransactionKind = .spend, category: SpendCategory? = nil, categoryID: String? = nil, pairID: String? = nil, isFee: Bool = false,
                displayName: String? = nil, note: String? = nil, excluded: Bool = false, createdAt: Date? = nil, logoURL: String? = nil) {
        self.id = id
        self.accountID = accountID
        self.amount = amount
        self.merchant = merchant
        self.merchantKey = Transaction.merchantKey(merchant)
        self.authorizedDate = authorizedDate
        self.date = date
        self.pending = pending
        self.kind = kind
        self.categoryID = categoryID ?? category?.rawValue
        self.pairID = pairID
        self.isFee = isFee
        self.displayName = displayName
        self.note = note
        self.excluded = excluded
        self.createdAt = createdAt
        self.logoURL = logoURL
    }

    /// The built-in category, when the id is one. Custom categories come back nil — use `CategorySet` for those.
    public var category: SpendCategory? {
        get { categoryID.flatMap(SpendCategory.init(rawValue:)) }
        set { categoryID = newValue?.rawValue }
    }

    /// The day the user actually paid: authorized when known, else the provider's date.
    public var displayDate: Date { authorizedDate ?? date }
    public var isOutflow: Bool { amount < 0 }
    public var magnitude: Decimal { amount < 0 ? -amount : amount }

    /// Normalized merchant key used for grouping and rules: lower-case letters and spaces only.

    public static func merchantKey(_ name: String) -> String {
        let lowered = name.lowercased()
        let cleaned = lowered.map { $0.isLetter || $0 == " " ? $0 : " " }
        return String(cleaned).split(separator: " ").joined(separator: " ")
    }
}
