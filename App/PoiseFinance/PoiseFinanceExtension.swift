import ExtensionFoundation
import FinanceKit
import OSLog

private let log = Logger(subsystem: "com.koliokolev.poise", category: "finance-extension")

/// Woken by the system when Wallet has new activity — at most hourly, app closed. Reads Apple Card, Apple Cash and
/// Savings and mirrors them to the server exactly as the app does, so a charge becomes a push and a fresh feed
/// without a launch. It never signs in: no session in the shared keychain means the user signed out, so it returns.
@main
final class PoiseFinanceExtension: BackgroundDeliveryExtension {
    required init() {}

    func didReceiveData(for types: [FinanceStore.BackgroundDataType]) async {
        guard (try? await Backend.client.auth.session) != nil else { log.notice("no session, nothing to sync"); return }
        let wallet = WalletSource(client: Backend.client)
        guard await wallet.isAuthorized() else { log.notice("wallet access is off, nothing to sync"); return }
        do {
            let summary = try await withDeadline(25, { try await wallet.sync() })
            log.info("background sync: \(summary.accounts) accounts, \(summary.transactions) rows")
        } catch {
            log.error("background sync failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    func willTerminate() async {}
}
