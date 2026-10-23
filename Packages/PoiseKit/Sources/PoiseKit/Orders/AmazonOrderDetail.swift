import Foundation

/// One line of an Amazon order: what it was, and what it cost.
public struct AmazonItem: Sendable, Equatable, Hashable, Codable {
    public let name: String
    public let price: Decimal?
    public let seller: String?

    public init(name: String, price: Decimal?, seller: String?) {
        self.name = name
        self.price = price
        self.seller = seller
    }

    /// Amazon titles are written for search, not for reading — the whole spec sheet in one line. This is the part a
    /// person would say out loud, cut at the first list of attributes.
    public var shortName: String {
        let head = name.split(separator: " - ", maxSplits: 1, omittingEmptySubsequences: true).first.map(String.init) ?? name
        let clipped = head.split(separator: ",", maxSplits: 1, omittingEmptySubsequences: true).first.map(String.init) ?? head
        let trimmed = clipped.trimmingCharacters(in: .whitespaces)
        return trimmed.count >= 12 ? trimmed : head.trimmingCharacters(in: .whitespaces)
    }
}

/// What was in an order, read from its own page on Amazon.
public struct AmazonOrderDetail: Sendable, Equatable, Codable {
    public let orderID: String
    public let items: [AmazonItem]
    public let subtotal: Decimal?
    public let tax: Decimal?
    public let total: Decimal?
    /// The day the order was placed — the day you actually bought it. Amazon authorises the card when it ships and
    /// posts later still, so this is the only date that answers "when did I buy this".
    public let placed: Date?
    /// Where a return has got to, in Amazon's own words: "Return started", "Refunded". The page says it plainly, so a
    /// waiting refund doesn't have to be a mystery the user resolves by hand.
    public let returnStatus: String?
    /// The sentence Amazon prints under that status, when there is one.
    public let returnNote: String?

    public init(orderID: String, items: [AmazonItem], subtotal: Decimal? = nil, tax: Decimal? = nil, total: Decimal? = nil,
                placed: Date? = nil, returnStatus: String? = nil, returnNote: String? = nil) {
        self.orderID = orderID
        self.items = items
        self.subtotal = subtotal
        self.tax = tax
        self.total = total
        self.placed = placed
        self.returnStatus = returnStatus
        self.returnNote = returnNote
    }

    /// A return Amazon has acknowledged but not finished. Waiting on this isn't late — it's in hand.
    public var returnInProgress: Bool {
        guard let returnStatus else { return false }
        return !returnStatus.lowercased().contains("refund") || returnStatus.lowercased().contains("will be")
    }
}

public enum AmazonOrderDetails {
    /// Reads an order page.
    ///
    /// The anchor is "Sold by:", which every real line of an order carries and none of the recommendation carousels
    /// below it do — so the ads that fill most of the page can't be mistaken for things you bought. The title is the
    /// line above the anchor, past the delivery chatter; the price is the first amount after it.
    public static func parse(_ text: String, orderID: String, calendar: Calendar = .current) -> AmazonOrderDetail {
        let lines = text.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }
        var items: [AmazonItem] = []

        for (i, line) in lines.enumerated() where line.hasPrefix("Sold by:") {
            let seller = line.dropFirst("Sold by:".count).trimmingCharacters(in: .whitespaces)
            guard let name = title(before: i, in: lines) else { continue }
            items.append(AmazonItem(name: name, price: firstMoney(after: i, in: lines), seller: seller.isEmpty ? nil : seller))
        }

        return AmazonOrderDetail(orderID: orderID, items: items,
                                 subtotal: money(labelled: "Item(s) Subtotal", in: lines),
                                 tax: money(labelled: "Estimated tax", in: lines),
                                 total: money(labelled: "Grand Total", in: lines),
                                 placed: placedDate(in: lines, calendar: calendar),
                                 returnStatus: returnState(in: lines)?.status,
                                 returnNote: returnState(in: lines)?.note)
    }

    /// Amazon prints the state of a return as its own line, with an explanation under it.
    private static func returnState(in lines: [String]) -> (status: String, note: String?)? {
        let known = ["Return started", "Return received", "Return complete", "Return completed", "Refunded",
                     "Refund issued", "Refund complete", "Return in progress", "Returned"]
        guard let i = lines.firstIndex(where: { line in known.contains { line.caseInsensitiveCompare($0) == .orderedSame } }) else { return nil }
        let next = i + 1 < lines.count ? lines[i + 1] : nil
        // The line under it is an explanation only when it reads like one, not when it's already the product title.
        let note = (next?.hasSuffix(".") ?? false) ? next : nil
        return (lines[i], note)
    }

    /// "Order placed September 5, 2026  Order # 113-…" — the date sits on the same line as the order number.
    private static func placedDate(in lines: [String], calendar: Calendar) -> Date? {
        guard let line = lines.first(where: { $0.hasPrefix("Order placed") }) else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "MMMM d, yyyy"
        let scanner = line.replacingOccurrences(of: "Order placed", with: "")
        for end in scanner.indices.reversed() {
            let candidate = String(scanner[scanner.startIndex ... end]).trimmingCharacters(in: .whitespaces)
            if let date = formatter.date(from: candidate) { return date }
        }
        return nil
    }

    /// Everything Amazon puts between the title and the seller — delivery status, packaging notes, gift messages.
    private static func isChatter(_ line: String) -> Bool {
        let openers = ["Delivered", "Arriving", "Shipped", "Not yet shipped", "Your package", "Your item", "Return",
                       "Refunded", "Order placed", "Ship to", "Payment method", "Gift", "Sold by"]
        return line.isEmpty || openers.contains { line.hasPrefix($0) } || amount(line) != nil
    }

    private static func title(before index: Int, in lines: [String]) -> String? {
        var i = index - 1
        while i >= 0 {
            let line = lines[i]
            // A title is the first real sentence above the seller. Short lines are labels and controls, not products.
            if !isChatter(line), line.count >= 12 { return line }
            i -= 1
        }
        return nil
    }

    private static func firstMoney(after index: Int, in lines: [String], within: Int = 8) -> Decimal? {
        for i in (index + 1) ..< min(index + 1 + within, lines.count) {
            if let value = amount(lines[i]) { return value }
            if lines[i].hasPrefix("Sold by:") { return nil }        // ran into the next item
        }
        return nil
    }

    /// A summary figure. The label and its amount may share a line or sit on two, so the amount is simply the next one.
    private static func money(labelled label: String, in lines: [String]) -> Decimal? {
        guard let i = lines.firstIndex(where: { $0.hasPrefix(label) }) else { return nil }
        if let inline = amount(String(lines[i].dropFirst(label.count))) { return inline }
        return firstMoney(after: i, in: lines, within: 3)
    }

    private static func amount(_ line: String) -> Decimal? {
        guard let dollar = line.firstIndex(of: "$") else { return nil }
        let negative = line.hasPrefix("-") || line.hasPrefix("\u{2212}")
        let digits = line[line.index(after: dollar)...].replacingOccurrences(of: ",", with: "")
        guard !digits.isEmpty, digits.allSatisfy({ $0.isNumber || $0 == "." }),
              digits.contains("."), let value = Decimal(string: digits, locale: Locale(identifier: "en_US_POSIX")) else { return nil }
        return negative ? -value : value
    }
}
