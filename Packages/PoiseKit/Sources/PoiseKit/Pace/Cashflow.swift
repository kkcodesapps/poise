import Foundation

/// One day of the next fourteen: what's expected to leave or land, and the spending balance after it.
public struct CashflowDay: Hashable, Sendable, Identifiable {
    /// Signed. `viaCard` names the card when the charge settles through its statement rather than leaving checking that day.
    public struct Line: Hashable, Sendable {
        public let name: String; public let amount: Decimal; public let viaCard: String?
        public init(name: String, amount: Decimal, viaCard: String? = nil) { self.name = name; self.amount = amount; self.viaCard = viaCard }
        public var movesCash: Bool { viaCard == nil }
    }
    public let date: Date
    public let lines: [Line]
    public let balanceAfter: Decimal
    public let isToday: Bool
    public var isCrunch: Bool { balanceAfter < 0 }
    public var hasIncome: Bool { lines.contains { $0.amount > 0 && $0.movesCash } }
    /// What actually leaves or lands in checking that day.
    public var cashMoved: Decimal { lines.filter(\.movesCash).reduce(0) { $0 + $1.amount } }
    public var id: Date { date }
}

public enum CashflowEngine {
    public static func nextDays(_ count: Int = 14, accounts: [Account], streams: [RecurringStream], transactions: [Transaction], now: Date, calendar: Calendar = .current, newCardsPay: CardPayment = .statement) -> [CashflowDay] {
        let today = calendar.startOfDay(for: now)
        var balance = accounts.filter { $0.role == .spending }.reduce(Decimal(0)) { $0 + $1.balance }
        let end = calendar.date(byAdding: .day, value: count - 1, to: today)!
        var byDay: [Date: [CashflowDay.Line]] = [:]
        // Card statements leave checking on their due date. Card payments never form streams, so nothing is counted twice.
        for a in accounts where !a.hidden {
            guard let next = a.nextDue(now: now, calendar: calendar), let amount = a.statementPayment(default: newCardsPay) else { continue }
            let day = calendar.startOfDay(for: next.date)
            if day > today, day <= end {
                byDay[day, default: []].append(.init(name: "\(a.name) statement\(next.isEstimate ? " (estimated)" : "")", amount: -amount))
            }
        }
        let cards = Dictionary(uniqueKeysWithValues: accounts.filter { $0.role == .credit }.map { ($0.id, $0.name) })
        for s in streams {
            // A subscription on a card is worth seeing, but it's the statement that leaves checking.
            let via = s.accountID.flatMap { cards[$0] }
            for d in s.occurrences(after: today.addingTimeInterval(-1), through: end, calendar: calendar) {
                let day = calendar.startOfDay(for: d)
                if day == today { continue }   // today's known charges are already in the feed / balance
                byDay[day, default: []].append(.init(name: s.merchant, amount: s.kind == .income ? s.amount : -s.amount, viaCard: via))
            }
        }
        // Today shows what's pending (already reflected in available balance, so not subtracted again). A card payment
        // is money leaving whatever it was paid from, never income — some banks sign it positive on the card — and the
        // pair is one movement, so only the side that actually moves cash is listed.
        let creditIDs = Set(accounts.filter { $0.role == .credit }.map(\.id))
        let todaysPending = transactions.filter { $0.pending && calendar.isDate($0.displayDate, inSameDayAs: today) }
        let cashSides = todaysPending.filter { $0.kind == .ccPayment && !creditIDs.contains($0.accountID) }
        let cashPairs = Set(cashSides.compactMap(\.pairID)), cashAmounts = Set(cashSides.map(\.magnitude))
        // A payment the card has counted and checking hasn't yet does leave today: it's in no balance, and its statement
        // already reads as paid.
        let inFlight = paymentsInFlight(accounts: accounts, transactions: transactions, now: now, calendar: calendar)
        let inFlightIDs = Set(inFlight.map(\.transactionID))
        let clearing = inFlight.map { CashflowDay.Line(name: "\($0.card) payment", amount: -$0.amount) }
        balance -= inFlight.reduce(Decimal(0)) { $0 + $1.amount }
        let pendingToday = todaysPending
            .filter { !inFlightIDs.contains($0.id) }
            // The card's copy of a payment that also left a spending account — same pair, or the same amount the same day.
            .filter { !($0.kind == .ccPayment && creditIDs.contains($0.accountID) && ($0.pairID.map(cashPairs.contains) == true || cashAmounts.contains($0.magnitude))) }
            .map { CashflowDay.Line(name: $0.merchant + " (pending)", amount: $0.kind == .ccPayment ? -$0.magnitude : $0.amount) }
        var out: [CashflowDay] = []
        var day = today
        while day <= end {
            let lines = day == today ? clearing + pendingToday : (byDay[day] ?? [])
            if day != today { balance += lines.filter(\.movesCash).reduce(0) { $0 + $1.amount } }
            out.append(CashflowDay(date: day, lines: lines, balanceAfter: balance, isToday: day == today))
            day = calendar.date(byAdding: .day, value: 1, to: day)!
        }
        return out
    }
}

/// A card payment the card has already counted and the account it's paid from hasn't yet.
public struct PaymentInFlight: Hashable, Sendable {
    public let transactionID: String
    public let card: String
    public let amount: Decimal
}

extension CashflowEngine {
    /// Payments sitting between a card and checking.
    ///
    /// Apple Card shows a payment the moment it's made; Chase takes the money a day or two later. In between, the card's
    /// statement reads as paid, so it's gone from the due date, while checking still holds the money, and the payment was
    /// in no number at all. A payment that has landed on a card with no withdrawal to match it yet is still on its way out
    /// — on a card whose payments have come out of a linked account before, so one paid from somewhere Poise can't see is
    /// never taken out of checking.
    ///
    /// `window` matches the transfer pairing's, so a withdrawal that turns up later always pairs with it and nothing is
    /// counted twice.
    public static func paymentsInFlight(accounts: [Account], transactions: [Transaction], now: Date, window: Int = 3, calendar: Calendar = .current) -> [PaymentInFlight] {
        let today = calendar.startOfDay(for: now)
        let spending = Set(accounts.filter { $0.role == .spending }.map(\.id))
        guard !spending.isEmpty else { return [] }
        let byID = Dictionary(transactions.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let byPair = Dictionary(grouping: transactions.filter { $0.pairID != nil }, by: { $0.pairID! })
        // The other half: by its id (the transfer pairing) or by a pair id both halves share (some providers).
        func partner(_ t: Transaction) -> Transaction? {
            guard let p = t.pairID else { return nil }
            return byID[p] ?? byPair[p]?.first { $0.id != t.id }
        }
        func age(_ t: Transaction) -> Int { calendar.dateComponents([.day], from: calendar.startOfDay(for: t.date), to: today).day ?? .max }
        var out: [PaymentInFlight] = []
        for card in accounts where card.role == .credit && !card.hidden {
            let landed = transactions.filter { $0.accountID == card.id && $0.amount > 0 && $0.kind != .refund }
            guard landed.contains(where: { partner($0).map { spending.contains($0.accountID) } == true }) else { continue }
            for t in landed where partner(t) == nil && (0...window).contains(age(t)) {
                // A withdrawal of the same size since then, paired or not, is this payment arriving.
                let arrived = transactions.contains { spending.contains($0.accountID) && $0.isOutflow && $0.magnitude == t.magnitude && age($0) <= age(t) + 1 }
                if !arrived { out.append(.init(transactionID: t.id, card: card.name, amount: t.magnitude)) }
            }
        }
        return out
    }
}
