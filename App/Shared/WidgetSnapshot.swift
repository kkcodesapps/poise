import Foundation

/// What the widgets show: the verdict at a glance, and the latest few charges. Written by the app after every
/// recompute into the shared app-group container; read by the widget extension.
struct WidgetSnapshot: Codable, Equatable {
    enum Status: String, Codable { case good, track, heads, empty }
    struct Row: Codable, Equatable, Identifiable { var id: String; var name: String; var amount: String; var pending: Bool }

    var status: Status
    /// "IN GOOD SHAPE" / "ON TRACK" / "HEADS UP" / "LINK A BANK"
    var statusLabel: String
    /// "$1,240" — or "—" when nothing is linked.
    var ahead: String
    /// "ahead through Fri" / "short on Mon"
    var aheadSub: String
    /// "31%"
    var kept: String
    var keptGood: Bool
    var latest: [Row]
    var updatedAt: Date

    static let appGroup = "group.com.koliokolev.poise"
    static let empty = WidgetSnapshot(status: .empty, statusLabel: "POISE", ahead: "—", aheadSub: "Link a bank to start", kept: "—", keptGood: false, latest: [], updatedAt: .distantPast)

    private static var url: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup)?.appendingPathComponent("widget.json")
    }

    static func load() -> WidgetSnapshot? {
        guard let url, let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(WidgetSnapshot.self, from: data)
    }

    func save() {
        guard let url = Self.url else { return }
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        if let data = try? encoder.encode(self) { try? data.write(to: url, options: .atomic) }
    }
}
