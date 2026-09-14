import Foundation
import Supabase
import PoiseKit

/// Reads the user's rows and maps them to the engine's models. The server is the source of truth.
struct Repository {
    let client: SupabaseClient

    struct Snapshot: Sendable {
        var accounts: [Account]
        var transactions: [Transaction]
        var streams: [RecurringStream]
        var lastSync: Date?
    }

    func load(days: Int = 90) async throws -> Snapshot {
        let since = Calendar.current.date(byAdding: .day, value: -days, to: .now) ?? .now
        async let accountRows: [AccountRow] = client.from("accounts").select().execute().value
        async let txnRows: [TransactionRow] = client.from("transactions").select()
            .is("deleted_at", value: nil)
            .gte("display_date", value: Self.day.string(from: since))
            .order("display_date", ascending: false)
            .limit(2000)
            .execute().value
        async let streamRows: [StreamRow] = client.from("streams").select().eq("status", value: "active").execute().value
        async let itemRows: [ItemRow] = client.from("items").select("id, status, last_synced_at, institution_name").execute().value

        let (a, t, s, items) = try await (accountRows, txnRows, streamRows, itemRows)
        let lastSync = items.compactMap { $0.last_synced_at.flatMap(Self.timestamp.date(from:)) }.max()
        return Snapshot(accounts: a.map(\.model), transactions: t.map(\.model), streams: s.map(\.model), lastSync: lastSync)
    }

    // MARK: rows → models

    private struct AccountRow: Decodable {
        let id: UUID, name: String, mask: String?, role: String, available: Double?, current: Double, currency: String
        var model: Account {
            Account(id: id.uuidString, name: name, mask: mask, role: AccountRole(rawValue: role) ?? .other,
                    available: available.map(Repository.decimal), current: Repository.decimal(current), currency: currency)
        }
    }

    private struct TransactionRow: Decodable {
        let id: UUID, account_id: UUID, amount: Double, merchant: String, authorized_date: String?, posted_date: String
        let pending: Bool, kind: String, category: String?, pair_id: UUID?
        var model: Transaction {
            Transaction(id: id.uuidString, accountID: account_id.uuidString, amount: Repository.decimal(amount), merchant: merchant,
                        authorizedDate: authorized_date.flatMap(Repository.day.date(from:)), date: Repository.day.date(from: posted_date) ?? .now,
                        pending: pending, kind: TransactionKind(rawValue: kind) ?? .spend, category: category.flatMap(SpendCategory.init(rawValue:)),
                        pairID: pair_id?.uuidString)
        }
    }

    private struct StreamRow: Decodable {
        let id: UUID, merchant: String, kind: String, cadence: String, amount_last: Double, amount_prev: Double?, last_seen: String, next_expected: String
        var model: RecurringStream {
            RecurringStream(id: id.uuidString, merchant: merchant, kind: StreamKind(rawValue: kind) ?? .bill, cadence: Cadence(rawValue: cadence) ?? .monthly,
                            amount: Repository.decimal(amount_last), previousAmount: amount_prev.map(Repository.decimal),
                            lastSeen: Repository.day.date(from: last_seen) ?? .now, nextExpected: Repository.day.date(from: next_expected) ?? .now)
        }
    }

    private struct ItemRow: Decodable { let id: UUID, status: String, last_synced_at: String?, institution_name: String? }

    /// Postgres numeric arrives as a JSON number; round-trip through two decimals so 62.4 never becomes 62.399999.
    static func decimal(_ d: Double) -> Decimal { Decimal(string: String(format: "%.2f", d)) ?? Decimal(d) }

    static let day: DateFormatter = {
        let f = DateFormatter(); f.calendar = Calendar(identifier: .iso8601); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "yyyy-MM-dd"; return f
    }()
    nonisolated(unsafe) static let timestamp: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]; return f
    }()
}
