import CryptoKit
import Foundation
import OSLog
import UIKit

private let log = Logger(subsystem: "com.koliokolev.poise", category: "logos")

/// Merchant logos, fetched once and kept: in memory for this run, on disk for the next. A logo already seen draws on the
/// first frame instead of flashing the glyph while it downloads again, and works offline.
final class LogoCache: @unchecked Sendable {
    static let shared = LogoCache()

    private let memory = NSCache<NSString, UIImage>()
    private let dir: URL
    private let lock = NSLock()
    private var inFlight: [URL: Task<UIImage?, Never>] = [:]
    private var missing: Set<URL> = []   // a dead link is asked for once per run, not on every scroll

    private init() {
        memory.countLimit = 400
        dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("logos", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    /// Only what's already in memory — cheap enough to call while drawing.
    func cached(_ url: URL) -> UIImage? { memory.object(forKey: url.absoluteString as NSString) }

    /// Memory, then disk, then the network. Two circles asking for the same logo share one download.
    func image(for url: URL) async -> UIImage? {
        if let image = cached(url) { return image }
        let task: Task<UIImage?, Never> = lock.withLock {
            if missing.contains(url) { return Task { nil } }
            if let running = inFlight[url] { return running }
            let task = Task.detached(priority: .userInitiated) { [self] in await load(url) }
            inFlight[url] = task
            return task
        }
        let image = await task.value
        lock.withLock {
            inFlight[url] = nil
            if image == nil { missing.insert(url) }
        }
        return image
    }

    private func load(_ url: URL) async -> UIImage? {
        let file = dir.appendingPathComponent(key(url))
        if let data = try? Data(contentsOf: file), let image = decode(data) { keep(image, for: url); return image }
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard (response as? HTTPURLResponse).map({ (200 ..< 300).contains($0.statusCode) }) ?? true, let image = decode(data) else { return nil }
            try? data.write(to: file, options: .atomic)
            keep(image, for: url)
            return image
        } catch {
            log.info("logo fetch failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    /// Decoded up front and shrunk to the largest circle the app draws, so scrolling never decodes on the main thread.
    private func decode(_ data: Data) -> UIImage? {
        guard let image = UIImage(data: data) else { return nil }
        let side: CGFloat = 64 * 3
        if max(image.size.width, image.size.height) > side {
            let scale = side / max(image.size.width, image.size.height)
            return image.preparingThumbnail(of: CGSize(width: image.size.width * scale, height: image.size.height * scale)) ?? image
        }
        return image.preparingForDisplay() ?? image
    }

    private func keep(_ image: UIImage, for url: URL) { memory.setObject(image, forKey: url.absoluteString as NSString) }

    private func key(_ url: URL) -> String {
        SHA256.hash(data: Data(url.absoluteString.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}
