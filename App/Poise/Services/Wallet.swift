import Foundation
import FinanceKit
import OSLog
import Supabase

private let log = Logger(subsystem: "com.koliokolev.poise", category: "wallet")

/// Apple Card, Apple Cash and Savings: read from Wallet on this iPhone and mirrored to the server like any other bank.
/// There's no webhook for these — the phone is the source — so the app syncs on launch, on foreground and on pull.
actor WalletSource {
    /// False outside supported regions, and always on the simulator, where FinanceKit traps instead of throwing.
    nonisolated static var isAvailable: Bool {
        #if targetEnvironment(simulator)
        false
        #else
        FinanceStore.isDataAvailable(.financialData)
        #endif
    }

    private let client: SupabaseClient
    private let store = FinanceStore.shared
    /// How far back a routine sync looks. Pending charges settle or vanish well inside this.
    private static let windowDays = 45
    private static let batch = 400

    init(client: SupabaseClient) { self.client = client }

    struct Summary: Sendable {
        var accounts = 0, transactions = 0
        var changes: Int { transactions }
    }

    func isAuthorized() async -> Bool { (try? await store.authorizationStatus()) == .authorized }

    /// Shows the system access sheet; on a yes, reads everything Wallet shares and sends it up.
    func connect() async throws -> Bool {
        guard try await store.requestAuthorization() == .authorized else { return false }
        _ = try await sync()
        return true
    }

    /// Accounts and balances as they are now, then each account's transactions: all of them until the server says it
    /// holds the full history, the last 45 days after that. The server drops rows in that window that Wallet no longer
    /// lists (dropped pre-auths), and it — not the phone — remembers which accounts are complete.
    func sync() async throws -> Summary {
        let accounts = try await store.accounts(query: AccountQuery())
        let balances = try await store.accountBalances(query: AccountBalanceQuery())
        let all = try await store.transactions(query: TransactionQuery())
        var summary = Summary(accounts: accounts.count)
        let complete = try await upload(Payload(accounts: accounts.map(Payload.Account.init), balances: balances.map(Payload.Balance.init))).complete

        let cutoff = Calendar.current.date(byAdding: .day, value: -Self.windowDays, to: Calendar.current.startOfDay(for: .now)) ?? .now
        for account in accounts {
            let key = account.id.uuidString
            let since: String? = complete.contains(key) ? Payload.day(cutoff) : nil
            let rows = all
                .filter { t in t.accountID == account.id && (since.map { Payload.day(t.transactionDate) >= $0 } ?? true) }
                .sorted { $0.transactionDate < $1.transactionDate }
            let prune = Payload.Prune(accountID: key, since: since, keep: rows.map(\.id.uuidString))
            let chunks = stride(from: 0, to: rows.count, by: Self.batch).map { Array(rows[$0..<min($0 + Self.batch, rows.count)]) }
            if chunks.isEmpty {
                try await upload(Payload(prune: prune))
            } else {
                for (i, chunk) in chunks.enumerated() {
                    try await upload(Payload(transactions: chunk.map(Payload.Transaction.init), prune: i == chunks.count - 1 ? prune : nil))
                }
            }
            summary.transactions += rows.count
        }
        log.info("wallet sync: \(summary.accounts) accounts, \(summary.transactions) transactions sent")
        return summary
    }

    private struct Receipt: Decodable { let complete: [String] }

    @discardableResult
    private func upload(_ payload: Payload) async throws -> Receipt {
        try await client.functions.invoke("financekit-sync", options: FunctionInvokeOptions(body: payload))
    }
}

extension WalletSource {
    /// What the server's `financekit-sync` reads. Amounts are unsigned; `debit` is Wallet's own indicator, decoded server-side.
    struct Payload: Encodable, Sendable {
        var accounts: [Account]? = nil
        var balances: [Balance]? = nil
        var transactions: [Transaction]? = nil
        var prune: Prune? = nil

        /// "These are all of this account's transactions since `since` (or ever, when nil) — drop anything else you hold."
        struct Prune: Encodable, Sendable { let accountID: String, since: String?, keep: [String] }

        struct Account: Encodable, Sendable {
            let id: String, name: String, description: String?, institution: String, currency: String, kind: String, creditLimit: Decimal?
            init(_ a: FinanceKit.Account) {
                id = a.id.uuidString; name = a.displayName; description = a.accountDescription; institution = a.institutionName; currency = a.currencyCode
                switch a {
                case .asset: kind = "asset"; creditLimit = nil
                case .liability(let l): kind = "liability"; creditLimit = l.creditInformation.creditLimit?.amount
                @unknown default: kind = "asset"; creditLimit = nil
                }
            }
        }

        struct Money: Encodable, Sendable {
            let amount: Decimal, debit: Bool
            init(_ b: FinanceKit.Balance) { amount = b.amount.amount; debit = b.creditDebitIndicator == .debit }
        }

        struct Balance: Encodable, Sendable {
            let accountID: String, available: Money?, booked: Money?, asOf: String
            init(_ b: AccountBalance) {
                accountID = b.accountID.uuidString
                available = b.available.map(Money.init); booked = b.booked.map(Money.init)
                asOf = ((b.booked ?? b.available)?.asOfDate ?? .now).formatted(.iso8601)
            }
        }

        struct Transaction: Encodable, Sendable {
            let id: String, accountID: String, amount: Decimal, currency: String, debit: Bool
            let description: String, merchant: String?, mcc: Int?, type: String, status: String, date: String, postedDate: String?
            init(_ t: FinanceKit.Transaction) {
                id = t.id.uuidString; accountID = t.accountID.uuidString
                amount = t.transactionAmount.amount; currency = t.transactionAmount.currencyCode
                debit = t.creditDebitIndicator == .debit
                description = t.transactionDescription; merchant = t.merchantName
                mcc = t.merchantCategoryCode.map { Int($0.rawValue) }
                type = String(describing: t.transactionType); status = String(describing: t.status)
                date = Payload.day(t.transactionDate); postedDate = t.postedDate.map(Payload.day)
            }
        }

        /// The calendar day where the phone is — Plaid's dates are local days too, so the feed groups both the same way.
        static func day(_ date: Date) -> String {
            let c = Calendar.current.dateComponents([.year, .month, .day], from: date)
            return String(format: "%04d-%02d-%02d", c.year ?? 1970, c.month ?? 1, c.day ?? 1)
        }
    }
}

enum WalletError: LocalizedError {
    case timedOut
    var errorDescription: String? { "Wallet took too long to answer. Try again in a moment." }
}

/// First caller wins — for continuations that several callbacks could try to resume.
final class Once: @unchecked Sendable {
    private let lock = NSLock(); private var done = false
    func first() -> Bool { lock.lock(); defer { lock.unlock() }; if done { return false }; done = true; return true }
}

/// Runs `work` but returns after `seconds` regardless, so a framework call that never comes back can't wedge the app.
func withDeadline<T: Sendable>(_ seconds: Double, _ work: @escaping @Sendable () async throws -> T) async throws -> T {
    let once = Once()
    return try await withCheckedThrowingContinuation { continuation in
        let job = Task {
            do { let value = try await work(); if once.first() { continuation.resume(returning: value) } }
            catch { if once.first() { continuation.resume(throwing: error) } }
        }
        Task {
            try? await Task.sleep(for: .seconds(seconds))
            if once.first() { job.cancel(); continuation.resume(throwing: WalletError.timedOut) }
        }
    }
}
