import Foundation
import AuthenticationServices
import CryptoKit
import LocalAuthentication
import Supabase

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
        if let name = credential.fullName, let given = name.givenName {
            _ = try? await client.auth.update(user: UserAttributes(data: ["full_name": .string([given, name.familyName].compactMap { $0 }.joined(separator: " "))]))
        }
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
