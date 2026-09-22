import Foundation

/// The lens the user never has to think about — but can set on their own categories.
public enum Lens: String, Codable, Sendable, CaseIterable {
    case needs, wants
    /// Money set aside (a "Kids savings" category): treated like savings — never spend.
    case kept
}

/// A category at runtime: one of the nine built-ins or one the user created. Ids: built-ins use the enum's raw value,
/// custom ones a UUID string.
public struct Category: Identifiable, Hashable, Codable, Sendable {
    public let id: String
    public var name: String
    public var symbol: String        // SF Symbol name
    public var lens: Lens
    public let builtIn: Bool
    public var sort: Int

    public init(id: String, name: String, symbol: String, lens: Lens, builtIn: Bool, sort: Int) {
        self.id = id; self.name = name; self.symbol = symbol; self.lens = lens; self.builtIn = builtIn; self.sort = sort
    }

    public static func builtIn(_ c: SpendCategory) -> Category {
        Category(id: c.rawValue, name: c.title, symbol: c.symbol, lens: c.lens == .needs ? .needs : .wants, builtIn: true, sort: SpendCategory.allCases.firstIndex(of: c) ?? 0)
    }
}

/// Every category the user can see, with lookups the engine needs. Built-ins can be re-lensed; custom ones added.
public struct CategorySet: Hashable, Sendable {
    public private(set) var all: [Category]
    private var byID: [String: Category]

    public init(_ categories: [Category]) {
        let builtIns = SpendCategory.allCases.map(Category.builtIn)
        var merged = builtIns
        for c in categories { if let i = merged.firstIndex(where: { $0.id == c.id }) { merged[i] = c } else { merged.append(c) } }
        all = merged.sorted { ($0.builtIn ? 1 : 0, $0.sort, $0.name) < ($1.builtIn ? 1 : 0, $1.sort, $1.name) }
        byID = Dictionary(uniqueKeysWithValues: all.map { ($0.id, $0) })
    }

    public static let builtIn = CategorySet([])

    public subscript(id: String?) -> Category? { id.flatMap { byID[$0] } }
    public var custom: [Category] { all.filter { !$0.builtIn } }
    public var builtIns: [Category] { all.filter(\.builtIn) }

    /// Lens for a transaction's category; unknown or missing → wants (the conservative call for spending).
    public func lens(_ id: String?) -> Lens { self[id]?.lens ?? .wants }
    public func name(_ id: String?) -> String { self[id]?.name ?? "Uncategorized" }
    public func symbol(_ id: String?) -> String { self[id]?.symbol ?? "ellipsis" }
    /// Resolves a missing or deleted category to the built-in "other".
    public func resolve(_ id: String?) -> Category { self[id] ?? Category.builtIn(.other) }
}

public extension SpendCategory {
    var symbol: String {
        switch self {
        case .home: "house"
        case .groceries: "cart"
        case .dining: "fork.knife"
        case .transport: "car"
        case .shopping: "bag"
        case .subscriptions: "arrow.clockwise"
        case .health: "heart"
        case .fun: "ticket"
        case .other: "ellipsis"
        }
    }
}
