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
    private struct ExchangeBody: Encodable { let public_token: String; let institution: Institution?; struct Institution: Encodable { let id: String; let name: String } }
    private struct ExchangeResponse: Decodable { let item_id: String; let accounts: Int }

    /// Returns nil when the user closes Link without finishing.
    func link() async throws -> Outcome? {
        let token: LinkTokenResponse = try await client.functions.invoke("plaid-link-token")
        guard let result = try await present(token: token.link_token) else { return nil }
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
        return try await withCheckedThrowingContinuation { continuation in
            let config = LinkTokenConfiguration(
                token: token,
                onSuccess: { success in
                    continuation.resume(returning: LinkResult(publicToken: success.publicToken, institutionID: success.metadata.institution.id, institutionName: success.metadata.institution.name))
                },
                onExit: { exit in
                    if let error = exit.error { continuation.resume(throwing: BackendError.link(error.errorMessage)) }
                    else { continuation.resume(returning: nil) }
                },
                onEvent: nil,
                onLoad: nil
            )
            do {
                let session = try Plaid.createPlaidLinkSession(configuration: config)
                self.session = session
                session.open(using: .viewController(vc))
            } catch {
                continuation.resume(throwing: BackendError.link(error.localizedDescription))
            }
        }
    }
}
