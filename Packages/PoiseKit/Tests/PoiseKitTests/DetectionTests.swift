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

    @Test func oneMerchantCanCarrySeveralStreams() {
        // Rent and its parking line land the same day under one name: two monthly bills, not a broken pattern.
        let rent = [7, 8, 9].flatMap { m in [Fix.tx("r\(m)", "chk", "-4110", "Moda Homes", on: Fix.day(2026, m, 2), category: .home), Fix.tx("p\(m)", "chk", "-200", "Moda Homes", on: Fix.day(2026, m, 2), category: .home)] }
        let streams = RecurringDetector.detect(rent, now: Fix.day(2026, 9, 20), calendar: Fix.calendar)
        #expect(streams.count == 2)
        let big = try! #require(streams.first { $0.amount == Fix.money("4110") }), small = try! #require(streams.first { $0.amount == Fix.money("200") })
        #expect(big.id == "spend|moda homes" && small.id == "spend|moda homes|2" && big.kind == StreamKind.bill)
        #expect(big.nextExpected == Fix.calendar.startOfDay(for: Fix.day(2026, 10, 2)) && big.transactionIDs == ["r7", "r8", "r9"])

        // Two Netflix plans two days apart: each keeps its own rhythm.
        let netflix = [7, 8, 9].flatMap { m in [Fix.tx("n\(m)", "card", "-26.99", "Netflix", on: Fix.day(2026, m, 13), category: .subscriptions), Fix.tx("o\(m)", "card", "-24.99", "Netflix", on: Fix.day(2026, m, 15), category: .subscriptions)] }
        let two = RecurringDetector.detect(netflix, now: Fix.day(2026, 9, 20), calendar: Fix.calendar)
        #expect(two.count == 2 && two.allSatisfy { $0.cadence == Cadence.monthly })
    }

    @Test func semimonthlyPayrollIsItsOwnRhythm() {
        // The 15th and the last day of the month, with the Friday-before rule: Aug 29 (the 31st was a Monday? no — a Sunday),
        // Sep 15, so the next one is Sep 30, then Oct 15.
        let pay = [Fix.tx("s0", "chk", "4557.32", "Squiz Payroll", on: Fix.day(2026, 7, 31), kind: .income), Fix.tx("s1", "chk", "4557.32", "Squiz Payroll", on: Fix.day(2026, 8, 14), kind: .income),
                   Fix.tx("s2", "chk", "4557.32", "Squiz Payroll", on: Fix.day(2026, 8, 31), kind: .income), Fix.tx("s3", "chk", "4557.33", "Squiz Payroll", on: Fix.day(2026, 9, 15), kind: .income)]
        let s = try! #require(RecurringDetector.detect(pay, now: Fix.day(2026, 9, 20), calendar: Fix.calendar).first)
        #expect(s.kind == StreamKind.income && s.cadence == Cadence.semimonthly && s.transactionIDs.count == 4)   // the 17-day gap stays in the chain
        #expect(s.nextExpected == Fix.calendar.startOfDay(for: Fix.day(2026, 9, 30)))
        #expect(Cadence.semimonthly.next(after: s.nextExpected, calendar: Fix.calendar) == Fix.calendar.startOfDay(for: Fix.day(2026, 10, 15)))
        // A year of paydays walks straight through February 2027 (the 28th is a Sunday → Fri the 26th) without stalling.
        let year = s.occurrences(after: Fix.day(2026, 9, 20), through: Fix.day(2027, 9, 20), calendar: Fix.calendar)
        #expect(year.count == 24 && year.contains(Fix.calendar.startOfDay(for: Fix.day(2027, 2, 26))) && year.contains(Fix.calendar.startOfDay(for: Fix.day(2027, 3, 15))))
    }

    @Test func duplicatesAndFees() {
        let rows = [
            Fix.tx("s1", "card", "-48.10", "Shell", on: Fix.day(2026, 9, 9), category: .transport),
            Fix.tx("s2", "card", "-48.10", "Shell", on: Fix.day(2026, 9, 9), category: .transport),
            Fix.tx("s3", "card", "-48.10", "Shell", on: Fix.day(2026, 9, 14), category: .transport),
            Transaction(id: "f1", accountID: "chk", amount: Fix.money("-3"), merchant: "ATM fee", date: Fix.day(2026, 7, 2), kind: .spend, category: .other, isFee: true),
            Transaction(id: "f2", accountID: "chk", amount: Fix.money("-35"), merchant: "Foreign transaction fee", date: Fix.day(2026, 8, 12), kind: .spend, category: .other, isFee: true),
        ]
        let dups = Anomalies.duplicates(in: rows, calendar: Fix.calendar)
        #expect(dups.count == 1 && dups.first?.second.id == "s2")

        // Not a double charge: a different card, the next day, a small amount, a habit, or a merchant the user muted.
        let twoCards = [Fix.tx("c1", "card", "-48.10", "Shell", on: Fix.day(2026, 9, 9)), Fix.tx("c2", "chk", "-48.10", "Shell", on: Fix.day(2026, 9, 9))]
        #expect(Anomalies.duplicates(in: twoCards, calendar: Fix.calendar).isEmpty)
        let nextDay = [Fix.tx("d1", "card", "-48.10", "Shell", on: Fix.day(2026, 9, 9)), Fix.tx("d2", "card", "-48.10", "Shell", on: Fix.day(2026, 9, 10))]
        #expect(Anomalies.duplicates(in: nextDay, calendar: Fix.calendar).isEmpty)
        let tolls = [Fix.tx("t1", "card", "-3.30", "Illinois Tollway", on: Fix.day(2026, 9, 9)), Fix.tx("t2", "card", "-3.30", "Illinois Tollway", on: Fix.day(2026, 9, 9))]
        #expect(Anomalies.duplicates(in: tolls, calendar: Fix.calendar).isEmpty)
        let habit = (0..<4).map { Fix.tx("h\($0)", "card", "-12.00", "Premier Car Wash", on: Fix.day(2026, 9, 2 + $0 * 2)) }
            + [Fix.tx("h4", "card", "-12.00", "Premier Car Wash", on: Fix.day(2026, 9, 14)), Fix.tx("h5", "card", "-12.00", "Premier Car Wash", on: Fix.day(2026, 9, 14))]
        #expect(Anomalies.duplicates(in: habit, calendar: Fix.calendar).isEmpty)
        #expect(Anomalies.duplicates(in: rows, muted: [Transaction.merchantKey("Shell")], calendar: Fix.calendar).isEmpty)

        // A refund that mirrors a charge is the opposite of a duplicate — even when a merchant rule stored it as spend.
        let mirrored = [
            Fix.tx("a1", "card", "-30.59", "Amazon", on: Fix.day(2026, 9, 14), category: .shopping),
            Transaction(id: "a2", accountID: "card", amount: Fix.money("30.59"), merchant: "Amazon", date: Fix.day(2026, 9, 14), kind: .spend, category: .shopping),
            Transaction(id: "a3", accountID: "card", amount: Fix.money("30.59"), merchant: "Amazon", date: Fix.day(2026, 9, 15), kind: .refund, category: .shopping),
        ]
        #expect(Anomalies.duplicates(in: mirrored).isEmpty)
        let fees = Anomalies.feesYearToDate(rows, now: now, calendar: Fix.calendar)
        #expect(fees.total == Fix.money("38") && fees.items.count == 2)
    }
}
