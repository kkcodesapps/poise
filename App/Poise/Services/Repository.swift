import Foundation
import Supabase
import PoiseKit

/// Reads the user's rows and maps them to the engine's models. The server is the source of truth.
struct Repository {
    let client: SupabaseClient

    struct Snapshot: Sendable {
        /// Accounts that count. Hidden ones are kept apart so the engine never sees them.
        var accounts: [Account]
        var hiddenAccounts: [Account]
        var transactions: [Transaction]
        var streams: [RecurringStream]
        var lastSync: Date?
        var institutions: [String]
        var relinkNeeded: [Item]
        var walletLinked: Bool
        var customCategories: [PoiseKit.Category]
        var watches: [Watch]
    }

    struct Item: Sendable, Identifiable, Hashable { let id: String; let institution: String; let status: String }

    func load(days: Int = 90) async throws -> Snapshot {
        let since = Calendar.current.date(byAdding: .day, value: -days, to: .now) ?? .now
        // Accounts first: hidden ones decide which transactions are worth fetching at all.
        async let accountRows: [AccountRow] = client.from("accounts").select().execute().value
        async let itemRows: [ItemRow] = client.from("items").select("id, provider, status, last_synced_at, institution_name").execute().value
        let (a, items) = try await (accountRows, itemRows)
        let institution = Dictionary(uniqueKeysWithValues: items.map { ($0.id.uuidString, $0.institution_name) })
        let all = a.map { $0.model(institution: institution[$0.item_id.uuidString] ?? nil) }
        let hidden = all.filter(\.hidden)

        var txnQuery = client.from("transactions").select()
            .is("deleted_at", value: nil)
            .gte("display_date", value: Self.day.string(from: since))
        if !hidden.isEmpty { txnQuery = txnQuery.not("account_id", operator: .in, value: "(\(hidden.map(\.id).joined(separator: ",")))") }
        async let txnRows: [TransactionRow] = txnQuery.order("display_date", ascending: false).limit(2000).execute().value
        async let streamRows: [StreamRow] = client.from("streams").select().eq("status", value: "active").execute().value
        async let catRows: [CategoryRow] = client.from("categories").select().order("sort").execute().value
        async let watchRows: [WatchRow] = client.from("watches").select().order("created_at", ascending: false).execute().value

        let (t, s, cats, ws) = try await (txnRows, streamRows, catRows, watchRows)
        let lastSync = items.compactMap { $0.last_synced_at.flatMap(Self.date(from:)) }.max()
        return Snapshot(accounts: all.filter { !$0.hidden }, hiddenAccounts: hidden, transactions: t.map(\.model), streams: s.map(\.model), lastSync: lastSync,
                        institutions: Array(Set(items.compactMap(\.institution_name))).sorted(),
                        relinkNeeded: items.filter { $0.status == "relink" }.map { Item(id: $0.id.uuidString, institution: $0.institution_name ?? "A bank", status: $0.status) },
                        walletLinked: items.contains { $0.provider == "financekit" },
                        customCategories: cats.map(\.model), watches: ws.map(\.model))
    }

    // MARK: rows → models

    private struct AccountRow: Decodable {
        let id: UUID, item_id: UUID, name: String, mask: String?, role: String, available: Double?, current: Double, currency: String
        let hidden: Bool, hidden_at: String?, balance_at: String?
        func model(institution: String?) -> Account {
            Account(id: id.uuidString, name: name, mask: mask, role: AccountRole(rawValue: role) ?? .other,
                    available: available.map(Repository.decimal), current: Repository.decimal(current), currency: currency,
                    institution: institution, itemID: item_id.uuidString, hidden: hidden,
                    hiddenAt: hidden_at.flatMap(Repository.date(from:)), balanceAt: balance_at.flatMap(Repository.date(from:)))
        }
    }

    private struct TransactionRow: Decodable {
        let id: UUID, account_id: UUID, amount: Double, merchant: String, authorized_date: String?, posted_date: String
        let pending: Bool, kind: String, category: String?, pair_id: UUID?, provider_category: String?
        var model: Transaction {
            Transaction(id: id.uuidString, accountID: account_id.uuidString, amount: Repository.decimal(amount), merchant: merchant,
                        authorizedDate: authorized_date.flatMap(Repository.day.date(from:)), date: Repository.day.date(from: posted_date) ?? .now,
                        pending: pending, kind: TransactionKind(rawValue: kind) ?? .spend, categoryID: category,
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

    private struct ItemRow: Decodable { let id: UUID, provider: String, status: String, last_synced_at: String?, institution_name: String? }

    private struct CategoryRow: Codable {
        var id: UUID?, user_id: String?, name: String, symbol: String, lens: String, sort: Int
        var model: PoiseKit.Category { PoiseKit.Category(id: id!.uuidString.lowercased(), name: name, symbol: symbol, lens: Lens(rawValue: lens) ?? .wants, builtIn: false, sort: sort) }
    }

    private struct WatchRow: Codable {
        var id: UUID?, user_id: String?, kind: String, transaction_id: UUID?, merchant: String, matcher: String, expected_amount: Double?, nudge_days: Int, note: String?, status: String
        var created_at: String?, resolved_at: String?, resolved_transaction_id: UUID?
        var model: Watch {
            Watch(id: id!.uuidString, kind: Watch.Kind(rawValue: kind) ?? .refund, transactionID: transaction_id?.uuidString, merchant: merchant, matcher: matcher,
                  expectedAmount: expected_amount.map(Repository.decimal), nudgeDays: nudge_days, note: note, status: Watch.Status(rawValue: status) ?? .waiting,
                  createdAt: created_at.flatMap(Repository.date(from:)) ?? .now, resolvedAt: resolved_at.flatMap(Repository.date(from:)), resolvedTransactionID: resolved_transaction_id?.uuidString)
        }
        static func from(_ w: Watch, userID: String) -> WatchRow {
            WatchRow(id: UUID(uuidString: w.id), user_id: userID, kind: w.kind.rawValue, transaction_id: w.transactionID.flatMap(UUID.init(uuidString:)), merchant: w.merchant, matcher: w.matcher,
                     expected_amount: w.expectedAmount.map { Double(truncating: $0 as NSDecimalNumber) }, nudge_days: w.nudgeDays, note: w.note, status: w.status.rawValue,
                     created_at: Repository.timestamp.string(from: w.createdAt), resolved_at: w.resolvedAt.map(Repository.timestamp.string(from:)), resolved_transaction_id: w.resolvedTransactionID.flatMap(UUID.init(uuidString:)))
        }
    }

    // MARK: categories

    func create(category name: String, symbol: String, lens: Lens) async throws -> PoiseKit.Category {
        let session = try await client.auth.session
        struct Insert: Encodable { let user_id: String; let name: String; let symbol: String; let lens: String; let sort: Int }
        let row: CategoryRow = try await client.from("categories").insert(Insert(user_id: session.user.id.uuidString, name: name, symbol: symbol, lens: lens.rawValue, sort: 0)).select().single().execute().value
        return row.model
    }

    func update(category c: PoiseKit.Category) async throws {
        struct Patch: Encodable { let name: String; let symbol: String; let lens: String; let sort: Int }
        try await client.from("categories").update(Patch(name: c.name, symbol: c.symbol, lens: c.lens.rawValue, sort: c.sort)).eq("id", value: c.id).execute()
    }

    /// Deletes a custom category; its charges and rules go back to the built-in "other" (the bank's suggestion is re-applied on the next sync).
    func delete(categoryID: String) async throws {
        struct Patch: Encodable { let category: String }
        try await client.from("transactions").update(Patch(category: "other")).eq("category", value: categoryID).execute()
        try await client.from("merchant_rules").update(Patch(category: "other")).eq("category", value: categoryID).execute()
        try await client.from("categories").delete().eq("id", value: categoryID).execute()
    }

    // MARK: watches

    func insert(watch: Watch) async throws {
        let session = try await client.auth.session
        try await client.from("watches").insert(WatchRow.from(watch, userID: session.user.id.uuidString)).execute()
    }

    func update(watch: Watch) async throws {
        struct Patch: Encodable { let status: String; let resolved_at: String?; let resolved_transaction_id: String?; let expected_amount: Double?; let nudge_days: Int; let note: String? }
        try await client.from("watches").update(Patch(status: watch.status.rawValue, resolved_at: watch.resolvedAt.map(Repository.timestamp.string(from:)), resolved_transaction_id: watch.resolvedTransactionID,
                                                      expected_amount: watch.expectedAmount.map { Double(truncating: $0 as NSDecimalNumber) }, nudge_days: watch.nudgeDays, note: watch.note)).eq("id", value: watch.id).execute()
    }

    func delete(watchID: String) async throws {
        try await client.from("watches").delete().eq("id", value: watchID).execute()
    }

    // MARK: writes

    /// A correction on one row. `kind` and `category` are the user's word; the server keeps `classified_by = user`.
    func update(transactionID: String, kind: TransactionKind, categoryID: String?) async throws {
        struct Patch: Encodable { let kind: String; let category: String?; let classified_by: String }
        try await client.from("transactions").update(Patch(kind: kind.rawValue, category: categoryID, classified_by: "user")).eq("id", value: transactionID).execute()
    }

    /// "Always file X under Y": stores the rule (applied to future syncs on the server) and rewrites the matching rows now.
    func upsertRule(merchant: String, kind: TransactionKind, categoryID: String?, applyTo ids: [String]) async throws {
        struct Rule: Encodable { let user_id: String; let matcher: String; let category: String?; let kind: String }
        let session = try await client.auth.session
        try await client.from("merchant_rules").upsert(Rule(user_id: session.user.id.uuidString, matcher: Transaction.merchantKey(merchant), category: categoryID, kind: kind.rawValue), onConflict: "user_id,matcher").execute()
        struct Patch: Encodable { let kind: String; let category: String?; let classified_by: String }
        if !ids.isEmpty {
            try await client.from("transactions").update(Patch(kind: kind.rawValue, category: categoryID, classified_by: "rule")).in("id", values: ids).execute()
        }
    }

    func update(accountID: String, role: AccountRole) async throws {
        struct Patch: Encodable { let role: String }
        try await client.from("accounts").update(Patch(role: role.rawValue)).eq("id", value: accountID).execute()
    }

    /// The user's own flag; nothing on the sync path writes it, so it survives every refresh.
    func update(accountID: String, hidden: Bool) async throws {
        struct Patch: Encodable { let hidden: Bool; let hidden_at: String? }
        let at = hidden ? Date.now.formatted(.iso8601) : nil
        try await client.from("accounts").update(Patch(hidden: hidden, hidden_at: at)).eq("id", value: accountID).execute()
    }

    /// Drops one institution: revoked at the provider, then its accounts and rows go with it.
    func disconnect(itemID: String) async throws {
        struct Body: Encodable { let item_id: String }
        try await client.functions.invoke("disconnect-item", options: FunctionInvokeOptions(body: Body(item_id: itemID)))
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
        var categoryLens: [String: String] = [:]     // built-in id → lens override
        var dismissedStreams: [String] = []          // "Not a subscription" — stream ids the detector should keep quiet about
    }

    private struct SettingsRow: Codable {
        var user_id: String?
        var payday_override: String?
        var pays_cc_in_full: Bool
        var kept_target: Double?
        var committed_savings: Double
        var notif_prefs: [String: Bool]
        var faceid: Bool
        var category_lens: [String: String]?
        var dismissed_streams: [String]?
    }

    func loadSettings() async throws -> Settings {
        let rows: [SettingsRow] = try await client.from("settings").select().limit(1).execute().value
        guard let r = rows.first else { return Settings() }
        return Settings(paydayOverride: r.payday_override.flatMap(Self.day.date(from:)), paysCardsInFull: r.pays_cc_in_full, keptTarget: r.kept_target,
                        committedSavings: Self.decimal(r.committed_savings), notifySpend: r.notif_prefs["spend"] ?? true,
                        notifyHeadsUp: r.notif_prefs["heads_up"] ?? true, notifyWeekly: r.notif_prefs["weekly_review"] ?? true, faceID: r.faceid, categoryLens: r.category_lens ?? [:],
                        dismissedStreams: r.dismissed_streams ?? [])
    }

    func save(_ s: Settings) async throws {
        let session = try await client.auth.session
        let row = SettingsRow(user_id: session.user.id.uuidString, payday_override: s.paydayOverride.map(Self.day.string(from:)), pays_cc_in_full: s.paysCardsInFull,
                              kept_target: s.keptTarget, committed_savings: Double(truncating: s.committedSavings as NSDecimalNumber),
                              notif_prefs: ["spend": s.notifySpend, "heads_up": s.notifyHeadsUp, "weekly_review": s.notifyWeekly], faceid: s.faceID, category_lens: s.categoryLens, dismissed_streams: s.dismissedStreams)
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
    nonisolated(unsafe) static let timestampPlain: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime]; return f
    }()
    /// Postgres omits fractional seconds when they are zero; accept both shapes.
    static func date(from iso: String) -> Date? { timestamp.date(from: iso) ?? timestampPlain.date(from: iso) }
}
