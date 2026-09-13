import Foundation
@testable import PoiseKit

/// Deterministic calendar + helpers shared by the engine tests.
enum Fix {
    static var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }

    static func day(_ y: Int, _ m: Int, _ d: Int) -> Date {
        calendar.date(from: DateComponents(year: y, month: m, day: d, hour: 12))!
    }

    static func money(_ s: String) -> Decimal { Decimal(string: s, locale: Locale(identifier: "en_US_POSIX"))! }

    static let checking = Account(id: "chk", name: "Checking", mask: "4821", role: .spending, available: money("1455"), current: money("1517.40"))
    static let savings = Account(id: "sav", name: "Savings", mask: "1190", role: .savings, current: money("8450"))
    static let card = Account(id: "card", name: "Sapphire", mask: "0930", role: .credit, current: money("-612.40"))
    static var accounts: [Account] { [checking, savings, card] }

    static func tx(_ id: String, _ account: String, _ amount: String, _ merchant: String, on date: Date, authorized: Date? = nil, pending: Bool = false, kind: TransactionKind = .spend, category: SpendCategory? = nil) -> Transaction {
        Transaction(id: id, accountID: account, amount: money(amount), merchant: merchant, authorizedDate: authorized, date: date, pending: pending, kind: kind, category: category)
    }
}
