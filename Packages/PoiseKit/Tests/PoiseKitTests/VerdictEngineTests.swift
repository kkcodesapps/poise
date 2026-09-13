import Foundation
import Testing
@testable import PoiseKit

struct VerdictEngineTests {
    let now = Fix.day(2026, 9, 15)
    let payday = Fix.day(2026, 9, 26)

    var streams: [RecurringStream] {
        [
            RecurringStream(id: "rent", merchant: "Rent", kind: .bill, cadence: .monthly, amount: Fix.money("1450"), lastSeen: Fix.day(2026, 8, 22), nextExpected: Fix.day(2026, 9, 22)),
            RecurringStream(id: "comed", merchant: "ComEd", kind: .bill, cadence: .monthly, amount: Fix.money("96.40"), lastSeen: Fix.day(2026, 8, 22), nextExpected: Fix.day(2026, 9, 22)),
            RecurringStream(id: "netflix", merchant: "Netflix", kind: .subscription, cadence: .monthly, amount: Fix.money("17.99"), previousAmount: Fix.money("15.49"), lastSeen: Fix.day(2026, 8, 24), nextExpected: Fix.day(2026, 9, 24)),
            RecurringStream(id: "pay", merchant: "Acme Payroll", kind: .income, cadence: .biweekly, amount: Fix.money("2150"), lastSeen: Fix.day(2026, 9, 12), nextExpected: Fix.day(2026, 9, 26)),
        ]
    }

    @Test func aheadFindsTheCrunchDay() {
        let input = VerdictInput(accounts: Fix.accounts, transactions: [], streams: streams, now: now, nextPayday: payday, calendar: Fix.calendar)
        let ahead = VerdictEngine.ahead(input)
        // 1455 − (1450 + 96.40) on the 22nd → −91.40, then −17.99 Netflix on the 24th.
        #expect(ahead.crunch?.date == Fix.calendar.startOfDay(for: Fix.day(2026, 9, 22)))
        #expect(ahead.crunch?.shortfall == Fix.money("91.40"))
        #expect(ahead.amount == Fix.money("-109.39"))
        #expect(ahead.through == Fix.calendar.startOfDay(for: payday))
    }

    @Test func aheadIsPositiveWhenBillsFit() {
        var rich = Fix.checking; rich.available = Fix.money("3000")
        let input = VerdictInput(accounts: [rich, Fix.savings], transactions: [], streams: streams, now: now, nextPayday: payday, committedSavings: Fix.money("300"), calendar: Fix.calendar)
        let ahead = VerdictEngine.ahead(input)
        #expect(ahead.crunch == nil)
        #expect(ahead.amount == Fix.money("1135.61"))   // 3000 − 1546.40 − 17.99 − 300
    }

    @Test func keptIsIncomeMinusNetSpend() {
        let rows = [
            Fix.tx("p", "chk", "2150", "Acme Payroll", on: Fix.day(2026, 9, 12), kind: .income),
            Fix.tx("g", "chk", "-141.10", "Trader Joe's", on: Fix.day(2026, 9, 13), category: .groceries),
            Fix.tx("d", "card", "-34.20", "DoorDash", on: Fix.day(2026, 9, 14), category: .dining),
            Fix.tx("r", "card", "18.20", "Amazon", on: Fix.day(2026, 9, 14), kind: .refund),
            Fix.tx("s", "sav", "300", "Transfer in", on: Fix.day(2026, 9, 13), kind: .transfer),
            Fix.tx("t", "chk", "-300", "Online transfer", on: Fix.day(2026, 9, 13), kind: .transfer),
            Fix.tx("cc", "chk", "-612.40", "Card payment", on: Fix.day(2026, 9, 5), kind: .ccPayment),
        ]
        let input = VerdictInput(accounts: Fix.accounts, transactions: rows, streams: [], now: now, expectedIncome: Fix.money("4300"), calendar: Fix.calendar)
        let kept = VerdictEngine.kept(input)
        // 2150 − (141.10 + 34.20 − 18.20) = 1992.90; the transfer to savings and the card payment are not spend.
        #expect(kept.keptSoFar == Fix.money("1992.90"))
        #expect(kept.expectedIncome == Fix.money("4300"))
        #expect(kept.onPacePercent > 0.5 && kept.onPacePercent < 1)
    }

    @Test func statusRules() {
        let ok = Ahead(amount: 1240, through: payday, crunch: nil)
        let short = Ahead(amount: -150, through: payday, crunch: Crunch(date: Fix.day(2026, 9, 22), shortfall: 150))
        #expect(VerdictEngine.status(ahead: ok, kept: Kept(keptSoFar: 1840, expectedIncome: 4300, onPacePercent: 0.31), target: 0.2, anomalies: 0) == .goodShape)
        #expect(VerdictEngine.status(ahead: ok, kept: Kept(keptSoFar: 720, expectedIncome: 4300, onPacePercent: 0.12), target: 0.2, anomalies: 0) == .onTrack)
        #expect(VerdictEngine.status(ahead: short, kept: Kept(keptSoFar: 460, expectedIncome: 4300, onPacePercent: 0.08), target: 0.2, anomalies: 0) == .headsUp)
        #expect(VerdictEngine.status(ahead: ok, kept: Kept(keptSoFar: 1840, expectedIncome: 4300, onPacePercent: 0.31), target: 0.2, anomalies: 1) == .headsUp)
    }

    @Test func paydayComesFromTheIncomeStream() {
        let input = VerdictInput(accounts: Fix.accounts, transactions: [], streams: streams, now: now, calendar: Fix.calendar)
        #expect(VerdictEngine.nextPayday(input) == Fix.day(2026, 9, 26))
    }

    @Test func displayDatePrefersAuthorized() {
        let t = Fix.tx("x", "chk", "-62.40", "Costco", on: Fix.day(2026, 9, 12), authorized: Fix.day(2026, 9, 9), pending: true)
        #expect(t.displayDate == Fix.day(2026, 9, 9))
    }
}
