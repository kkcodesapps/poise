import Foundation
import OSLog

private let log = Logger(subsystem: "com.koliokolev.poise", category: "cache")

/// The last good load, on disk, so the next open shows yesterday's numbers instantly and offline while the refresh runs.
/// Keyed by user; protected until first unlock like the rest of the phone's data.
enum SnapshotCache {
    struct Payload: Codable { var userID: String; var snapshot: Repository.Snapshot; var settings: Repository.Settings; var savedAt: Date }

    private static var url: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("snapshot.json")
    }

    static func load(for userID: String) -> Payload? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        guard let p = try? decoder.decode(Payload.self, from: data), p.userID == userID else { return nil }
        return p
    }

    static func save(_ snapshot: Repository.Snapshot, _ settings: Repository.Settings, for userID: String) {
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(Payload(userID: userID, snapshot: snapshot, settings: settings, savedAt: .now)) else { return }
        do { try data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication]) }
        catch { log.error("cache write failed: \(error.localizedDescription, privacy: .public)") }
    }

    static func clear() { try? FileManager.default.removeItem(at: url) }
}
