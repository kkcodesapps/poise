import Foundation

/// A charge the user asked Poise to keep an eye on.
public struct Watch: Identifiable, Hashable, Codable, Sendable {
    public enum Kind: String, Codable, Sendable { case refund, merchant }
    public enum Status: String, Codable, Sendable { case waiting, overdue, arrived, watching, triggered, closed
        public var isOpen: Bool { self == .waiting || self == .overdue || self == .watching }
    }
    public let id: String
    public let kind: Kind
    public var transactionID: String?
    public var merchant: String
    public var matcher: String
    public var expectedAmount: Decimal?
    public var nudgeDays: Int
    public var note: String?
    public var status: Status
    public var createdAt: Date
    public var resolvedAt: Date?
    public var resolvedTransactionID: String?

    public init(id: String = UUID().uuidString, kind: Kind, transactionID: String? = nil, merchant: String, matcher: String? = nil, expectedAmount: Decimal? = nil, nudgeDays: Int = 14, note: String? = nil, status: Status? = nil, createdAt: Date = .now, resolvedAt: Date? = nil, resolvedTransactionID: String? = nil) {
        self.id = id; self.kind = kind; self.transactionID = transactionID; self.merchant = merchant; self.matcher = matcher ?? Transaction.merchantKey(merchant)
        self.expectedAmount = expectedAmount; self.nudgeDays = nudgeDays; self.note = note; self.status = status ?? (kind == .refund ? .waiting : .watching)
        self.createdAt = createdAt; self.resolvedAt = resolvedAt; self.resolvedTransactionID = resolvedTransactionID
    }
}

public enum WatchEngine {
    /// Re-derives every open watch's status from the transactions. Closed / resolved watches are left alone.
    public static func evaluate(_ watches: [Watch], transactions: [Transaction], now: Date, calendar: Calendar = .current) -> [Watch] {
        var used = Set(watches.compactMap(\.resolvedTransactionID))
        return watches.map { w in
            guard w.status.isOpen else { return w }
            var out = w
            let since = w.transactionID.flatMap { id in transactions.first { $0.id == id }?.displayDate } ?? w.createdAt
            switch w.kind {
            case .refund:
                let match = transactions.filter { $0.kind == .refund && $0.merchantKey == w.matcher && $0.displayDate >= since && !used.contains($0.id) && $0.magnitude >= (w.expectedAmount ?? 0) - Decimal(0.01) }
                    .sorted { $0.displayDate < $1.displayDate }.first
                if let match {
                    used.insert(match.id); out.status = .arrived; out.resolvedAt = match.displayDate; out.resolvedTransactionID = match.id
                } else {
                    let days = calendar.dateComponents([.day], from: since, to: now).day ?? 0
                    out.status = days > w.nudgeDays ? .overdue : .waiting
                }
            case .merchant:
                let hit = transactions.filter { ($0.kind == .spend || $0.kind == .untracked) && $0.merchantKey == w.matcher && $0.displayDate > w.createdAt && $0.id != w.transactionID }
                    .sorted { $0.displayDate < $1.displayDate }.first
                if let hit { out.status = .triggered; out.resolvedAt = hit.displayDate; out.resolvedTransactionID = hit.id }
            }
            return out
        }
    }

    public static func insights(_ watches: [Watch], transactions: [Transaction], now: Date, calendar: Calendar = .current) -> [Insight] {
        var out: [Insight] = []
        for w in watches {
            let since = w.transactionID.flatMap { id in transactions.first { $0.id == id }?.displayDate } ?? w.createdAt
            switch w.status {
            case .triggered:
                let hit = transactions.first { $0.id == w.resolvedTransactionID }
                out.append(Insight(id: "watch-hit-\(w.id)-\(w.resolvedTransactionID ?? "")", kind: .watchTriggered, tone: .heads, title: "\(w.merchant) charged you again",
                                   body: "\(hit?.magnitude.moneyString(cents: true) ?? "") on \((hit?.displayDate ?? now).formatted(.dateTime.month(.abbreviated).day())) — you asked to be told.", rank: 2))
            case .overdue:
                let days = calendar.dateComponents([.day], from: since, to: now).day ?? 0
                out.append(Insight(id: "watch-overdue-\(w.id)", kind: .refundOverdue, tone: .heads, title: "Still waiting on \(w.merchant)'s refund",
                                   body: "\((w.expectedAmount ?? 0).moneyString(cents: true)) · \(days) days. Worth a nudge.", rank: 4))
            case .arrived:
                if let r = w.resolvedAt, (calendar.dateComponents([.day], from: r, to: now).day ?? 99) <= 7 {
                    let days = calendar.dateComponents([.day], from: since, to: r).day ?? 0
                    out.append(Insight(id: "watch-arrived-\(w.id)", kind: .refundArrived, tone: .good, title: "\(w.merchant) refund arrived",
                                       body: "\((w.expectedAmount ?? 0).moneyString(cents: true)) back after \(days) day\(days == 1 ? "" : "s"). Watch closed.", rank: 6))
                }
            default: break
            }
        }
        return out
    }
}
