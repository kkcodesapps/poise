import Foundation
import Testing
@testable import PoiseKit

struct DetectionTests {
    let now = Fix.day(2026, 9, 15)

    func monthly(_ id: String, _ merchant: String, _ amounts: [String], day: Int, category: SpendCategory = .subscriptions) -> [PoiseKit.Transaction] {
        amounts.enumerated().map { i, a in Fix.tx("\(id)\(i)", "card", "-\(a)", merchant, on: Fix.day(2026, 6 + i, day), category: category) }
    }

    @Test func findsMonthlySubscriptionAndPriceCreep() {
        let rows = monthly("n", "Netflix", ["15.49", "15.49", "15.49", "17.99"], day: 24)
        let streams = RecurringDetector.detect(rows, now: now, calendar: Fix.calendar)
        let s = try! #require(streams.first { $0.merchant == "Netflix" })
        #expect(s.cadence == Cadence.monthly)
        #expect(s.kind == StreamKind.subscription)
        #expect(s.amount == Fix.money("17.99") && s.previousAmount == Fix.money("15.49") && s.priceWentUp)
        #expect(s.nextExpected == Fix.calendar.startOfDay(for: Fix.day(2026, 10, 24)))
    }

    @Test func rentIsABillAndBiweeklyPayIsIncome() {
        var rows = monthly("r", "Tectra Inc", ["1450", "1450", "1450"], day: 22, category: .home)
        for i in 0..<4 { rows.append(Fix.tx("p\(i)", "chk", "2150", "Acme Payroll", on: Fix.calendar.date(byAdding: .day, value: 14 * i, to: Fix.day(2026, 7, 31))!, kind: .income)) }
        let streams = RecurringDetector.detect(rows, now: now, calendar: Fix.calendar)
        #expect(streams.first { $0.merchant == "Tectra Inc" }?.kind == StreamKind.bill)
        let pay = try! #require(streams.first { $0.merchant == "Acme Payroll" })
        #expect(pay.kind == StreamKind.income && pay.cadence == Cadence.biweekly)
        #expect(pay.nextExpected == Fix.calendar.startOfDay(for: Fix.day(2026, 9, 25)))
    }

    @Test func irregularAmountsOrGapsAreNotStreams() {
        let irregular = monthly("i", "Amazon", ["12.00", "80.00", "33.50"], day: 3, category: .shopping)
        let ended = monthly("e", "Old Gym", ["40", "40"], day: 5)   // last seen July 5 → two missed periods by Sep 15
        let streams = RecurringDetector.detect(irregular + ended, now: now, calendar: Fix.calendar)
        #expect(streams.isEmpty)
    }

    @Test func refundLinksToTheOriginalCharge() {
        let rows = [
            Fix.tx("u1", "card", "-500", "United Airlines", on: Fix.day(2026, 8, 27), category: .fun),
            Fix.tx("u2", "card", "500", "United Airlines", on: Fix.day(2026, 9, 9), kind: .refund),
            Fix.tx("u3", "card", "-500", "United Airlines", on: Fix.day(2026, 5, 1), category: .fun),   // too old
        ]
        let out = RefundMatcher.match(rows, calendar: Fix.calendar)
        #expect(out[1].pairID == "u1" && out[0].pairID == "u2" && out[2].pairID == nil)
    }

    @Test func duplicatesAndFees() {
        let rows = [
            Fix.tx("s1", "card", "-48.10", "Shell", on: Fix.day(2026, 9, 9), category: .transport),
            Fix.tx("s2", "card", "-48.10", "Shell", on: Fix.day(2026, 9, 9), category: .transport),
            Fix.tx("s3", "card", "-48.10", "Shell", on: Fix.day(2026, 9, 14), category: .transport),
            Transaction(id: "f1", accountID: "chk", amount: Fix.money("-3"), merchant: "ATM fee", date: Fix.day(2026, 7, 2), kind: .spend, category: .other, isFee: true),
            Transaction(id: "f2", accountID: "chk", amount: Fix.money("-35"), merchant: "Foreign transaction fee", date: Fix.day(2026, 8, 12), kind: .spend, category: .other, isFee: true),
        ]
        let dups = Anomalies.duplicates(in: rows)
        #expect(dups.count == 1 && dups.first?.second.id == "s2")
        let fees = Anomalies.feesYearToDate(rows, now: now, calendar: Fix.calendar)
        #expect(fees.total == Fix.money("38") && fees.items.count == 2)
    }
}
