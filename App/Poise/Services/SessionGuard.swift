import Foundation
import Supabase

/// Every renewal of the sign-in passes through here, the app's and the Finance extension's alike.
///
/// The two share one session in the keychain, and each renewal hands out a new refresh token and retires the old one.
/// Supabase reads a retired token coming back as a stolen one and ends the session for good, and the library then deletes
/// it from the keychain. That signed the phone out on 2026-10-30: one side read the token, was suspended, and sent it
/// hours after the other side had renewed. So the token is read again at the moment the request leaves, and the new
/// session goes into the keychain the moment it arrives, before anything can suspend the process in between.
final class SessionGuard: URLProtocol, @unchecked Sendable {
    /// What the Supabase client sends through. Only renewals are touched; everything else goes out as it came.
    static let session: URLSession = {
        let configuration = URLSessionConfiguration.default
        configuration.protocolClasses = [SessionGuard.self] + (configuration.protocolClasses ?? [])
        return URLSession(configuration: configuration)
    }()
    /// The renewal itself goes out on a plain session, so it isn't caught here a second time.
    private static let network = URLSession(configuration: .default)

    override class func canInit(with request: URLRequest) -> Bool {
        guard let url = request.url, url.path.hasSuffix("/auth/v1/token") else { return false }
        return URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.contains { $0.name == "grant_type" && $0.value == "refresh_token" } ?? false
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    private var work: Task<Void, Never>?

    override func startLoading() {
        let request = request
        // URLProtocol predates Sendable; its client is safe to call from any thread.
        let box = Unchecked(self)
        work = Task {
            let loader = box.value
            do {
                let (data, response) = try await Self.renew(request)
                loader.client?.urlProtocol(loader, didReceive: response, cacheStoragePolicy: .notAllowed)
                loader.client?.urlProtocol(loader, didLoad: data)
                loader.client?.urlProtocolDidFinishLoading(loader)
            } catch {
                loader.client?.urlProtocol(loader, didFailWithError: error)
            }
        }
    }

    override func stopLoading() { work?.cancel() }

    private struct Body: Codable { let refresh_token: String }
    private struct Unchecked<Value>: @unchecked Sendable { let value: Value; init(_ value: Value) { self.value = value } }

    private static func renew(_ original: URLRequest) async throws -> (Data, URLResponse) {
        var request = original
        // The keychain holds the newest token either side has; the one in the request may be hours old. (The stream goes
        // first: clearing it after setting the body clears the body too.)
        let body = try stored().map { try JSONEncoder().encode(Body(refresh_token: $0.refreshToken)) } ?? body(of: original)
        request.httpBodyStream = nil
        request.httpBody = body
        let (data, response) = try await network.data(for: request)
        if (response as? HTTPURLResponse)?.statusCode == 200,
           let session = try? AuthClient.Configuration.jsonDecoder.decode(Session.self, from: data),
           let encoded = try? JSONEncoder().encode(session) {
            // Written the way the library writes it, so it reads this back as its own.
            try? Backend.storage.store(key: Backend.storageKey, value: encoded)
        }
        return (data, response)
    }

    private static func stored() -> Session? {
        guard let data = try? Backend.storage.retrieve(key: Backend.storageKey) else { return nil }
        return try? JSONDecoder().decode(Session.self, from: data)
    }

    /// A body handed to URLSession reaches a protocol as a stream.
    private static func body(of request: URLRequest) -> Data? {
        if let body = request.httpBody { return body }
        guard let stream = request.httpBodyStream else { return nil }
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while stream.hasBytesAvailable {
            let read = stream.read(&buffer, maxLength: buffer.count)
            guard read > 0 else { break }
            data.append(buffer, count: read)
        }
        return data
    }
}
