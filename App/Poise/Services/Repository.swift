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
        var institutions: [String]
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
        return Snapshot(accounts: a.map(\.model), transactions: t.map(\.model), streams: s.map(\.model), lastSync: lastSync,
                        institutions: Array(Set(items.compactMap(\.institution_name))).sorted())
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
        let pending: Bool, kind: String, category: String?, pair_id: UUID?, provider_category: String?
        var model: Transaction {
            Transaction(id: id.uuidString, accountID: account_id.uuidString, amount: Repository.decimal(amount), merchant: merchant,
                        authorizedDate: authorized_date.flatMap(Repository.day.date(from:)), date: Repository.day.date(from: posted_date) ?? .now,
                        pending: pending, kind: TransactionKind(rawValue: kind) ?? .spend, category: category.flatMap(SpendCategory.init(rawValue:)),
                        pairID: pair_id?.uuidString, isFee: provider_category?.hasPrefix("BANK_FEES") ?? false)
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

    // MARK: writes

    /// A correction on one row. `kind` and `category` are the user's word; the server keeps `classified_by = user`.
    func update(transactionID: String, kind: TransactionKind, category: SpendCategory?) async throws {
        struct Patch: Encodable { let kind: String; let category: String?; let classified_by: String }
        try await client.from("transactions").update(Patch(kind: kind.rawValue, category: category?.rawValue, classified_by: "user")).eq("id", value: transactionID).execute()
    }

    /// "Always file X under Y": stores the rule (applied to future syncs on the server) and rewrites the matching rows now.
    func upsertRule(merchant: String, kind: TransactionKind, category: SpendCategory?, applyTo ids: [String]) async throws {
        struct Rule: Encodable { let user_id: String; let matcher: String; let category: String?; let kind: String }
        let session = try await client.auth.session
        try await client.from("merchant_rules").upsert(Rule(user_id: session.user.id.uuidString, matcher: Transaction.merchantKey(merchant), category: category?.rawValue, kind: kind.rawValue), onConflict: "user_id,matcher").execute()
        struct Patch: Encodable { let kind: String; let category: String?; let classified_by: String }
        if !ids.isEmpty {
            try await client.from("transactions").update(Patch(kind: kind.rawValue, category: category?.rawValue, classified_by: "rule")).in("id", values: ids).execute()
        }
    }

    func update(accountID: String, role: AccountRole) async throws {
        struct Patch: Encodable { let role: String }
        try await client.from("accounts").update(Patch(role: role.rawValue)).eq("id", value: accountID).execute()
    }

    // MARK: settings

    struct Settings: Codable, Sendable, Equatable {
        var paydayOverride: Date?
        var paysCardsInFull = true
        var keptTarget: Double?           // nil = beat last month
        var committedSavings: Decimal = 0
        var notifySpend = true
        var notifyHeadsUp = true
        var notifyWeekly = true
        var faceID = false
    }

    private struct SettingsRow: Codable {
        var user_id: String?
        var payday_override: String?
        var pays_cc_in_full: Bool
        var kept_target: Double?
        var committed_savings: Double
        var notif_prefs: [String: Bool]
        var faceid: Bool
    }

    func loadSettings() async throws -> Settings {
        let rows: [SettingsRow] = try await client.from("settings").select().limit(1).execute().value
        guard let r = rows.first else { return Settings() }
        return Settings(paydayOverride: r.payday_override.flatMap(Self.day.date(from:)), paysCardsInFull: r.pays_cc_in_full, keptTarget: r.kept_target,
                        committedSavings: Self.decimal(r.committed_savings), notifySpend: r.notif_prefs["spend"] ?? true,
                        notifyHeadsUp: r.notif_prefs["heads_up"] ?? true, notifyWeekly: r.notif_prefs["weekly_review"] ?? true, faceID: r.faceid)
    }

    func save(_ s: Settings) async throws {
        let session = try await client.auth.session
        let row = SettingsRow(user_id: session.user.id.uuidString, payday_override: s.paydayOverride.map(Self.day.string(from:)), pays_cc_in_full: s.paysCardsInFull,
                              kept_target: s.keptTarget, committed_savings: Double(truncating: s.committedSavings as NSDecimalNumber),
                              notif_prefs: ["spend": s.notifySpend, "heads_up": s.notifyHeadsUp, "weekly_review": s.notifyWeekly], faceid: s.faceID)
        try await client.from("settings").upsert(row, onConflict: "user_id").execute()
    }

    /// Postgres numeric arrives as a JSON number; round-trip through two decimals so 62.4 never becomes 62.399999.
    static func decimal(_ d: Double) -> Decimal { Decimal(string: String(format: "%.2f", d)) ?? Decimal(d) }

    static let day: DateFormatter = {
        let f = DateFormatter(); f.calendar = Calendar(identifier: .iso8601); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "yyyy-MM-dd"; return f
    }()
    nonisolated(unsafe) static let timestamp: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]; return f
    }()
}
