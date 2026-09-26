import Foundation
import UIKit
import LinkKit
import Supabase

/// Runs Plaid Link end to end: token from the server → Link UI → public token back to the server.
@MainActor
final class BankLinker {
    private let client: SupabaseClient
    private var session: PlaidLinkSession?

    init(client: SupabaseClient) { self.client = client }

    struct Outcome: Sendable { let itemID: String; let accounts: Int }
    private struct LinkResult: Sendable { let publicToken: String; let institutionID: String; let institutionName: String }

    private struct LinkTokenResponse: Decodable { let link_token: String }
    private struct LinkTokenBody: Encodable { let item_id: String? }
    private struct ExchangeBody: Encodable { let public_token: String; let institution: Institution?; struct Institution: Encodable { let id: String; let name: String } }
    private struct ExchangeResponse: Decodable { let item_id: String; let accounts: Int }

    /// Returns nil when the user closes Link without finishing. Pass an item id to run Link in update mode (relink).
    func link(relink itemID: String? = nil) async throws -> Outcome? {
        let token: LinkTokenResponse = try await client.functions.invoke("plaid-link-token", options: FunctionInvokeOptions(body: LinkTokenBody(item_id: itemID)))
        guard let result = try await present(token: token.link_token) else { return nil }
        if let itemID {
            // Update mode: the item already exists; Link just repaired the login. Tell the server to mark it healthy and resync.
            struct RepairBody: Encodable { let item_id: String }
            try await client.functions.invoke("plaid-exchange", options: FunctionInvokeOptions(body: RepairBody(item_id: itemID)))
            return Outcome(itemID: itemID, accounts: 0)
        }
        let institution = ExchangeBody.Institution(id: result.institutionID, name: result.institutionName)
        let body = ExchangeBody(public_token: result.publicToken, institution: institution)
        let res: ExchangeResponse = try await client.functions.invoke("plaid-exchange", options: FunctionInvokeOptions(body: body))
        return Outcome(itemID: res.item_id, accounts: res.accounts)
    }

    private func present(token: String) async throws -> LinkResult? {
        guard let vc = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene }).flatMap(\.windows).first(where: \.isKeyWindow)?.rootViewController else {
            throw BackendError.noWindow
        }
        // Link must be presented from whatever is on top — the profile sheet, usually — not from the root, which is
        // already presenting that sheet and would refuse a second presentation without telling anyone.
        var top = vc
        while let next = top.presentedViewController { top = next }
        let presenter = top
        let once = Once()
        return try await withCheckedThrowingContinuation { continuation in
            let config = LinkTokenConfiguration(
                token: token,
                onSuccess: { success in
                    guard once.first() else { return }
                    continuation.resume(returning: LinkResult(publicToken: success.publicToken, institutionID: success.metadata.institution.id, institutionName: success.metadata.institution.name))
                },
                onExit: { exit in
                    guard once.first() else { return }
                    if let error = exit.error { continuation.resume(throwing: BackendError.link(error.errorMessage)) }
                    else { continuation.resume(returning: nil) }
                },
                onEvent: nil,
                onLoad: nil
            )
            do {
                let session = try Plaid.createPlaidLinkSession(configuration: config)
                self.session = session
                session.open(using: .viewController(presenter))
                // If nothing is on screen a moment later the presentation failed; say so rather than wait forever.
                Task { @MainActor in
                    try? await Task.sleep(for: .seconds(3))
                    if presenter.presentedViewController == nil, once.first() { continuation.resume(throwing: BackendError.link("Couldn't open the bank picker. Try again.")) }
                }
            } catch {
                if once.first() { continuation.resume(throwing: BackendError.link(error.localizedDescription)) }
            }
        }
    }
}
