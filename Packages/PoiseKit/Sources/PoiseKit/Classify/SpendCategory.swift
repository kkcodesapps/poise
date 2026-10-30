import Foundation

/// Ten buckets: what a charge was *for*. Whether it repeats — subscription or bill — is a separate answer on the stream.
public enum SpendCategory: String, Codable, Sendable, CaseIterable {
    case home, groceries, dining, transport, shopping, entertainment, tech, health, fun, other

    /// The lens the user never configures. Transfers into savings are the third bucket: kept.
    public enum Lens: String, Sendable { case needs, wants }

    public var lens: Lens {
        switch self {
        case .home, .groceries, .transport, .health: .needs
        case .dining, .shopping, .entertainment, .tech, .fun, .other: .wants
        }
    }

    public var title: String {
        switch self {
        case .home: "Home"
        case .groceries: "Groceries"
        case .dining: "Dining"
        case .transport: "Transport"
        case .shopping: "Shopping"
        case .entertainment: "Entertainment"
        case .tech: "Tech"
        case .health: "Health"
        case .fun: "Fun"
        case .other: "Other"
        }
    }

    /// The category that used to be "subscriptions", for rows and caches written before it was split up.
    public static func migrated(_ id: String?) -> String? { id == "subscriptions" ? SpendCategory.entertainment.rawValue : id }
}
