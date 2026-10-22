import Foundation

/// An order number Amazon shows against one of its own charges.
///
/// Banks never carry it: Chase can open an Amazon charge in the Amazon app only because Amazon and Chase share a
/// co-brand feed, and nothing of that reaches an aggregator. The one place it is visible to the person who paid is
/// Amazon's own payments page, which lists every charge with its order. That is what this reads.
public struct AmazonOrder: Sendable, Equatable, Hashable {
    /// Amazon's order number, `113-6576175-6286635`. Store-only purchases carry a different, unlinkable id.
    public let id: String
    /// The day Amazon took the money. A bank posts it the same day or up to three days later.
    public let date: Date
    /// Signed the way the feed is: negative is a charge, positive a refund.
    public let amount: Decimal
    /// What Amazon calls the charge — "AMZN Mktp US", "Amazon.com". The bank's descriptor echoes it.
    public let descriptor: String

    public init(id: String, date: Date, amount: Decimal, descriptor: String) {
        self.id = id
        self.date = date
        self.amount = amount
        self.descriptor = descriptor
    }

    /// Opens the Amazon app on this order, or the site when the app isn't installed.
    public var url: URL { AmazonOrders.url(for: id) }
}

public enum AmazonOrders {
    public static func url(for orderID: String) -> URL {
        URL(string: "https://www.amazon.com/gp/css/order-details?orderID=\(orderID)")!
    }

    /// Where the orders are listed, and the only page this feature reads.
    public static let transactionsPage = URL(string: "https://www.amazon.com/cpe/yourpayments/transactions")!

    // Amazon renders the same list differently to a phone and a desktop — one line per field in one, several fields to
    // a line in the other — so nothing here may depend on where the line breaks fall. Only three things are looked for,
    // wherever they sit: a day, a signed amount, and an order number. A store purchase carries a UUID instead of an
    // order number and nothing can open it, so the pattern simply doesn't match those.
    private static let dayPattern = #"(January|February|March|April|May|June|July|August|September|October|November|December)\s+\d{1,2},\s+\d{4}"#
    private static let amountPattern = #"[-−+]?\$\d[\d,]*\.\d{2}"#
    private static let orderPattern = #"Order\s*#\s*(\d{3}-\d{7}-\d{7})"#

    private enum Marker {
        case day(Date), amount(Decimal), order(String)
    }

    /// Reads Amazon's payments page and returns every order on it.
    ///
    /// The page is a run of blocks — a date heading, then a card, an amount and an order per charge — and the reading
    /// is positional rather than line-based: each order takes the day above it and the amount nearest it.
    public static func parse(_ text: String, calendar: Calendar = .current) -> [AmazonOrder] {
        let day = DateFormatter()
        day.locale = Locale(identifier: "en_US_POSIX")
        day.timeZone = calendar.timeZone
        day.dateFormat = "MMMM d, yyyy"

        let ns = text as NSString
        let whole = NSRange(location: 0, length: ns.length)
        var found: [(at: Int, marker: Marker)] = []

        for match in regex(dayPattern).matches(in: text, range: whole) {
            let raw = ns.substring(with: match.range).replacingOccurrences(of: "\u{00a0}", with: " ")
            if let d = day.date(from: raw.replacingOccurrences(of: "  ", with: " ")) {
                found.append((match.range.location, .day(d)))
            }
        }
        for match in regex(amountPattern).matches(in: text, range: whole) {
            if let value = money(ns.substring(with: match.range)) {
                found.append((match.range.location, .amount(value)))
            }
        }
        for match in regex(orderPattern).matches(in: text, range: whole) {
            found.append((match.range.location, .order(ns.substring(with: match.range(at: 1)))))
        }
        found.sort { $0.at < $1.at }

        // Each order takes the day most recently seen above it, and the amount closest to it — the one just before it
        // on a desktop layout, the one just after on a phone, but never one that belongs to a neighbouring charge.
        var orders: [AmazonOrder] = []
        var currentDay: Date?
        var claimed = Set<Int>()
        for (i, entry) in found.enumerated() {
            switch entry.marker {
            case .day(let d): currentDay = d
            case .amount: break
            case .order(let id):
                guard let currentDay, let amount = claimAmount(in: found, for: i, claimed: &claimed) else { continue }
                orders.append(AmazonOrder(id: id, date: currentDay, amount: amount, descriptor: descriptor(after: entry.at, in: ns)))
            }
        }
        return orders
    }

    /// The amount belonging to the order at `index`: the nearest unclaimed one, looking up first and then down, and
    /// never across a date heading or another order — so two charges on the same day can't end up sharing a figure.
    private static func claimAmount(in found: [(at: Int, marker: Marker)], for index: Int, claimed: inout Set<Int>) -> Decimal? {
        func take(_ range: StrideThrough<Int>) -> Decimal? {
            for j in range {
                switch found[j].marker {
                case .order, .day: return nil
                case .amount(let a) where !claimed.contains(j): claimed.insert(j); return a
                case .amount: continue
                }
            }
            return nil
        }
        if index > 0, let before = take(stride(from: index - 1, through: 0, by: -1)) { return before }
        if index + 1 < found.count, let after = take(stride(from: index + 1, through: found.count - 1, by: 1)) { return after }
        return nil
    }

    /// What Amazon calls the charge, taken from the rest of its line. Never used for matching — only for showing.
    private static func descriptor(after location: Int, in ns: NSString) -> String {
        let rest = NSRange(location: location, length: ns.length - location)
        let line = ns.rangeOfCharacter(from: .newlines, options: [], range: rest)
        guard line.location != NSNotFound else { return "" }
        let from = line.location + line.length
        let next = ns.rangeOfCharacter(from: .newlines, options: [], range: NSRange(location: from, length: ns.length - from))
        let end = next.location == NSNotFound ? ns.length : next.location
        return ns.substring(with: NSRange(location: from, length: end - from)).trimmingCharacters(in: .whitespaces)
    }

    private static func regex(_ pattern: String) -> NSRegularExpression {
        // The patterns are literals checked by the tests; a throw here would mean a typo, not a runtime condition.
        try! NSRegularExpression(pattern: pattern)
    }

    private static func money(_ token: String) -> Decimal? {
        guard let dollar = token.firstIndex(of: "$") else { return nil }
        let negative = token.hasPrefix("-") || token.hasPrefix("\u{2212}")
        let digits = token[token.index(after: dollar)...].replacingOccurrences(of: ",", with: "")
        guard let value = Decimal(string: digits, locale: Locale(identifier: "en_US_POSIX")) else { return nil }
        return negative ? -value : value
    }

    /// Pairs Amazon's orders to the charges Poise already has, and returns transaction id → order number.
    ///
    /// Amount is the key: within a few days no two Amazon charges land on the same cent. The date only has to be close,
    /// because Amazon's date is when it took the money and the bank's is when it posted. Nothing is paired twice, and a
    /// charge keeps the order nearest it in time, so a repeated amount can't drag an order onto the wrong week.
    public static func match(_ orders: [AmazonOrder], to transactions: [Transaction], calendar: Calendar = .current) -> [String: String] {
        let candidates = transactions.filter { $0.merchantKey.hasPrefix("amazon") }
        guard !candidates.isEmpty, !orders.isEmpty else { return [:] }

        // Claims are per listing, not per order number: one order shows up twice when it's refunded, and both the
        // charge and the refund belong to it. Deduplicating by order number threw the second one away.
        struct Pair { let transaction: String; let listing: Int; let order: String; let distance: TimeInterval }
        var pairs: [Pair] = []
        for (listing, order) in orders.enumerated() {
            for t in candidates where t.amount == order.amount {
                guard let gap = closestGap(of: t, to: order.date) else { continue }
                pairs.append(Pair(transaction: t.id, listing: listing, order: order.id, distance: gap))
            }
        }
        pairs.sort { $0.distance == $1.distance ? ($0.transaction, $0.listing) < ($1.transaction, $1.listing) : $0.distance < $1.distance }

        var taken: Set<String> = [], claimed: Set<Int> = [], out: [String: String] = [:]
        for p in pairs where !taken.contains(p.transaction) && !claimed.contains(p.listing) {
            taken.insert(p.transaction); claimed.insert(p.listing)
            out[p.transaction] = p.order
        }
        return out
    }

    /// How far a charge sits from the day Amazon took the money, or nil if it's too far to be the same thing.
    ///
    /// A charge has two dates and Amazon's day falls between them: the bank authorises when the order is placed, days
    /// before Amazon ships and charges, and posts days after. Measuring from only one of them — the authorised date —
    /// put orders two days out of reach and lost them.
    private static func closestGap(of t: Transaction, to day: Date) -> TimeInterval? {
        let gaps = Set([t.displayDate, t.date]).map { $0.timeIntervalSince(day) }
        let usable = gaps.filter { $0 >= -Self.window.before && $0 <= Self.window.after }
        return usable.map(abs).min()
    }

    /// The bank authorises up to three days before Amazon charges, and posts up to four days after.
    private static let window = (before: 3.5 * 86_400, after: 4.5 * 86_400)
}
