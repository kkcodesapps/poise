import Foundation
import AuthenticationServices
import CryptoKit
import LocalAuthentication
import Supabase
import UIKit

/// Sign in with Apple (native id-token flow) and the Face ID gate.
enum Auth {
    // MARK: Apple

    /// Random nonce: the raw value goes to Supabase, its SHA-256 goes into the Apple request.
    static func makeNonce() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return bytes.map { String(format: "%02x", $0) }.joined()
    }

    static func sha256(_ s: String) -> String {
        SHA256.hash(data: Data(s.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    /// Signs in with Apple's identity token. If the current session is anonymous, its data is moved to the new user first.
    static func signIn(with credential: ASAuthorizationAppleIDCredential, nonce: String, client: SupabaseClient) async throws {
        guard let tokenData = credential.identityToken, let idToken = String(data: tokenData, encoding: .utf8) else { throw BackendError.link("Apple didn't return an identity token.") }
        let previous = try? await client.auth.session
        let wasAnonymous = previous?.user.isAnonymous ?? false
        try await client.auth.signInWithIdToken(credentials: .init(provider: .apple, idToken: idToken, nonce: nonce))
        if wasAnonymous, let old = previous?.accessToken {
            struct Body: Encodable { let previous_token: String }
            try await client.functions.invoke("migrate-user", options: FunctionInvokeOptions(body: Body(previous_token: old)))
        }
        // The one-time code lets the server keep a revocable token, so "Delete everything" can end the Apple sign-in too.
        if let codeData = credential.authorizationCode, let code = String(data: codeData, encoding: .utf8) {
            struct Code: Encodable { let code: String }
            _ = try? await client.functions.invoke("apple-token", options: FunctionInvokeOptions(body: Code(code: code)))
        }
        if let name = credential.fullName, let given = name.givenName {
            _ = try? await client.auth.update(user: UserAttributes(data: ["full_name": .string([given, name.familyName].compactMap { $0 }.joined(separator: " "))]))
        }
    }

    /// Opening: a new user is made only on a phone no one has used yet. Where someone was signed in and the session is
    /// gone, this returns them instead, for the signed-out screen: a new account there opens empty and looks like
    /// everything was wiped, as it did on 2026-10-30.
    @MainActor static func resume(client: SupabaseClient) async throws -> LastUser? {
        if client.auth.currentSession != nil {
            do { _ = try await client.auth.session; return nil }
            catch {
                // A renewal the server refused takes the session with it; a dropped connection leaves it for next time.
                guard client.auth.currentSession == nil, let last = LastUser.stored else { throw error }
                return last
            }
        }
        // Nothing read can also mean the keychain hasn't opened yet: it does at the first unlock after a restart.
        guard UIApplication.shared.isProtectedDataAvailable else { throw BackendError.locked }
        if let last = LastUser.stored { return last }
        try await client.auth.signInAnonymously()
        return nil
    }

    // MARK: Face ID

    static var canUseBiometrics: Bool {
        LAContext().canEvaluatePolicy(.deviceOwnerAuthentication, error: nil)
    }

    /// Face ID / Touch ID with passcode fallback. Returns false if the user cancels.
    static func authenticate(reason: String = "Unlock Poise") async -> Bool {
        let context = LAContext()
        context.localizedCancelTitle = "Cancel"
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: nil) else { return true }
        return (try? await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason)) ?? false
    }
}

/// Who was last signed in on this phone, kept so a missing session reads as someone signed out, never as someone new.
struct LastUser: Equatable {
    let id: String
    /// On an Apple ID, so Sign in with Apple brings the account back. The automatic first-launch account can't be.
    let onAppleID: Bool

    static var stored: LastUser? {
        guard let id = UserDefaults.standard.string(forKey: "lastUserID") else { return nil }
        return LastUser(id: id, onAppleID: UserDefaults.standard.bool(forKey: "lastUserOnAppleID"))
    }
    static func remember(_ user: User) {
        UserDefaults.standard.set(user.id.uuidString, forKey: "lastUserID")
        UserDefaults.standard.set(!user.isAnonymous, forKey: "lastUserOnAppleID")
    }
    /// Signing out on purpose, deleting everything and starting over: the next opening is a first one.
    static func forget() {
        UserDefaults.standard.removeObject(forKey: "lastUserID")
        UserDefaults.standard.removeObject(forKey: "lastUserOnAppleID")
    }
}
