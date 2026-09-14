import Foundation
import Supabase

/// The one Supabase client. The publishable key is safe to ship; every table is behind row-level security.
enum Backend {
    static let url = URL(string: "https://ckncxuxpianojeskebnt.supabase.co")!
    static let publishableKey = "sb_publishable_HQufvSN3H4OjAz3LW0EUYg_fhiBrxPu"

    static let client = SupabaseClient(supabaseURL: url, supabaseKey: publishableKey)

    /// Signs in if there is no session yet. Anonymous for now; Sign in with Apple comes later and links to the same user.
    static func ensureSession() async throws {
        if (try? await client.auth.session) != nil { return }
        try await client.auth.signInAnonymously()
    }
}

enum BackendError: LocalizedError {
    case noWindow
    case link(String)

    var errorDescription: String? {
        switch self {
        case .noWindow: "Couldn’t find a window to present the bank link."
        case .link(let message): message
        }
    }
}
