import Foundation
import Supabase

/// The one Supabase client. The publishable key is safe to ship; every table is behind row-level security.
enum Backend {
    static let url = URL(string: "https://ckncxuxpianojeskebnt.supabase.co")!
    static let publishableKey = "sb_publishable_HQufvSN3H4OjAz3LW0EUYg_fhiBrxPu"

    /// The app's own keychain group. The Finance extension lists it too, so a background sync runs on the same session.
    static let keychainGroup = "D6937U28B4.com.koliokolev.poise"

    /// Where the session lives: on a phone, the shared keychain group, so the Finance extension is signed in as the app is.
    static let storage: any AuthLocalStorage = {
        #if targetEnvironment(simulator)
        KeychainLocalStorage()
        #else
        KeychainLocalStorage(service: "supabase.gotrue.swift", accessGroup: keychainGroup)
        #endif
    }()
    /// The library's own default key, spelled out so `SessionGuard` reads the same item it does.
    static let storageKey = "sb-\(url.host!.split(separator: ".")[0])-auth-token"

    static let client = SupabaseClient(supabaseURL: url, supabaseKey: publishableKey,
                                       options: .init(auth: .init(storage: storage, storageKey: storageKey), global: .init(session: SessionGuard.session)))
}

enum BackendError: LocalizedError {
    case noWindow
    case link(String)
    case locked

    var errorDescription: String? {
        switch self {
        case .noWindow: "Couldn’t find a window to present the bank link."
        case .link(let message): message
        case .locked: "Unlock your iPhone and Poise will open."
        }
    }
}
