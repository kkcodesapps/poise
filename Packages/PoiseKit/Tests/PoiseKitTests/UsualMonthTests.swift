import Foundation
import Testing
@testable import PoiseKit

struct UsualMonthTests {
    var october: DateInterval { Periods.window(.month, containing: Fix.day(2026, 10, 15), calendar: Fix.calendar) }
    let afterOctober = Fix.day(2026, 11, 6)

    var rows: [PoiseKit.Transaction] {
        [
            Fix.tx("s7", "card", "-300", "Target", on: Fix.day(2026, 7, 4), category: .shopping),
            Fix.tx("s8", "card", "-100", "Target", on: Fix.day(2026, 8, 4), category: .shopping),
            Fix.tx("s9", "card", "-200", "Target", on: Fix.day(2026, 9, 20), category: .shopping),
            Fix.tx("s10", "card", "-500", "Target", on: Fix.day(2026, 10, 4), category: .shopping),
            Fix.tx("g7", "card", "-400", "Jewel", on: Fix.day(2026, 7, 5), category: .groceries),
            Fix.tx("g8", "card", "-500", "Jewel", on: Fix.day(2026, 8, 5), category: .groceries),
            Fix.tx("g9", "card", "-600", "Jewel", on: Fix.day(2026, 9, 5), category: .groceries),
            Fix.tx("g10", "card", "-450", "Jewel", on: Fix.day(2026, 10, 5), category: .groceries),
            Fix.tx("o7", "card", "-3000", "One-off", on: Fix.day(2026, 7, 6), category: .other),
            Fix.tx("o10", "card", "-10", "Odd", on: Fix.day(2026, 10, 6), category: .other),
            Fix.tx("h10", "card", "-20", "Pharmacy", on: Fix.day(2026, 10, 7), category: .health),
        ]
    }

    func compute(_ rows: [PoiseKit.Transaction], now: Date) -> (UsualMonth?, Breakdown) {
        let b = CategoryBreakdown.compute(transactions: rows, period: .month, window: october, now: now, calendar: Fix.calendar)
        return (UsualMonth.compute(transactions: rows, window: october, now: now, calendar: Fix.calendar), b)
    }

    @Test func usualIsTheAverageOfTheThreeMonthsBefore() throws {
        let (u, b) = compute(rows, now: afterOctober)
        let usual = try #require(u)
        #expect(usual.months == 3 && !usual.inProgress)
        #expect(usual.entry("shopping") == .init(usual: 200, low: 100, high: 300))
        #expect(usual.gap(try #require(b.rows.first { $0.categoryID == "shopping" })) == 300)
    }

    @Test func aMonthWithoutTheCategoryCountsAsZero() throws {
        let usual = try #require(compute(rows, now: afterOctober).0)
        #expect(usual.entry("other") == .init(usual: 1000, low: 0, high: 3000))
    }

    @Test func standingNeedsTheRangeLeft() throws {
        let (u, b) = compute(rows, now: afterOctober)
        let usual = try #require(u)
        func standing(_ id: String) throws -> UsualMonth.Standing { usual.standing(try #require(b.rows.first { $0.categoryID == id })) }
        #expect(try standing("shopping") == .over)
        #expect(try standing("groceries") == .within)
        #expect(try standing("health") == .within)   // no history, no range to leave
    }

    @Test func otherRanksLastHoweverBigItsGap() throws {
        let (u, b) = compute(rows, now: afterOctober)
        let ranked = try #require(u).ranked(b.rows).map(\.categoryID)
        #expect(ranked == ["shopping", "groceries", "health", "other"])
    }

    @Test func theScaleReachesTheFurthestMarkRoundedUp() throws {
        let (u, b) = compute(rows, now: afterOctober)
        #expect(try #require(u).scale(b.rows) == 300)   // Shopping's gap; Other's $2,000 swing doesn't stretch it
        #expect(try #require(u).scale(b.rows.filter { $0.categoryID == "health" }) == 100)
    }

    @Test func aMonthInProgressIsMeasuredAgainstTheSameDays() throws {
        let usual = try #require(compute(rows, now: Fix.day(2026, 10, 6)).0)
        #expect(usual.inProgress)
        // September's shopping landed on the 20th, so by the 6th it hadn't happened yet.
        #expect(usual.entry("shopping") == .init(usual: (Decimal(400) / 3).roundedToCents, low: 0, high: 300))
    }

    @Test func noEarlierMonthsMeansNoUsual() {
        #expect(compute(rows.filter { $0.id.hasSuffix("10") }, now: afterOctober).0 == nil)
    }

    @Test func daysAddUpToTheMonthAndNetRefunds() {
        let refund = Transaction(id: "r", accountID: "card", amount: Fix.money("100"), merchant: "Target", date: Fix.day(2026, 10, 4), kind: .refund, category: .shopping, pairID: "s10")
        let b = compute(rows + [refund], now: afterOctober).1
        let days = b.days(calendar: Fix.calendar)
        #expect(days.count == 31)
        #expect(days[3].amount == 400 && days[3].transactions.count == 2)
        #expect(days.reduce(Decimal(0)) { $0 + $1.amount } == b.total)
    }
}
