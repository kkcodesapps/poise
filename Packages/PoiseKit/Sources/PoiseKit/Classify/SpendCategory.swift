import Foundation

/// Nine buckets. No sub-categories, none custom.
public enum SpendCategory: String, Codable, Sendable, CaseIterable {
    case home, groceries, dining, transport, shopping, subscriptions, health, fun, other

    /// The lens the user never configures. Transfers into savings are the third bucket: kept.
    public enum Lens: String, Sendable { case needs, wants }

    public var lens: Lens {
        switch self {
        case .home, .groceries, .transport, .health: .needs
        case .dining, .shopping, .subscriptions, .fun, .other: .wants
        }
    }

    public var title: String {
        switch self {
        case .home: "Home"
        case .groceries: "Groceries"
        case .dining: "Dining"
        case .transport: "Transport"
        case .shopping: "Shopping"
        case .subscriptions: "Subscriptions"
        case .health: "Health"
        case .fun: "Fun"
        case .other: "Other"
        }
    }
}
