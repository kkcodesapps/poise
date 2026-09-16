import Foundation
import Testing
@testable import PoiseKit

struct PaceAndInsightTests {
    let now = Fix.day(2026, 9, 15)

    var rows: [PoiseKit.Transaction] {
        [
            Fix.tx("a", "card", "-200", "DoorDash", on: Fix.day(2026, 9, 3), category: .dining),
            Fix.tx("b", "card", "-100", "Trader Joe's", on: Fix.day(2026, 9, 10), category: .groceries),
            Fix.tx("c", "card", "-50", "Uber", on: Fix.day(2026, 9, 12), category: .transport),
            Fix.tx("d", "card", "-100", "DoorDash", on: Fix.day(2026, 8, 5), category: .dining),
            Fix.tx("e", "card", "-150", "Trader Joe's", on: Fix.day(2026, 8, 20), category: .groceries),
            Fix.tx("f", "card", "-60", "Uber", on: Fix.day(2026, 8, 25), category: .transport),
            Fix.tx("p", "chk", "2150", "Acme Payroll", on: Fix.day(2026, 9, 12), kind: .income),
        ]
    }

    @Test func paceProjectsAndRanksMovers() {
        let pace = PaceEngine.pace(transactions: rows, streams: [], now: now, calendar: Fix.calendar)
        #expect(pace.spendSoFar == Fix.money("350"))
        #expect(pace.lastMonthTotal == Fix.money("310"))
        #expect(pace.lastMonthSameDay == Fix.money("100"))          // only DoorDash on Aug 5 falls before the 15th
        #expect(pace.wants == Fix.money("200") && pace.needs == Fix.money("150"))
        // projected = 350 + (200 / 15) × 15 remaining days = 550
        #expect(pace.projected == Fix.money("550"))
        #expect(pace.movers.first?.category == SpendCategory.dining && pace.movers.first?.delta == Fix.money("100"))
        #expect(pace.cumulative.count == 30 && pace.cumulative[14].thisMonth == Fix.money("350") && pace.cumulative[15].thisMonth == nil)
    }

    @Test func cashflowWalksTheNextTwoWeeks() {
        let streams = [
            RecurringStream(id: "rent", merchant: "Rent", kind: .bill, cadence: .monthly, amount: Fix.money("1450"), lastSeen: Fix.day(2026, 8, 22), nextExpected: Fix.day(2026, 9, 22)),
            RecurringStream(id: "pay", merchant: "Acme Payroll", kind: .income, cadence: .biweekly, amount: Fix.money("2150"), lastSeen: Fix.day(2026, 9, 12), nextExpected: Fix.day(2026, 9, 26)),
        ]
        let days = CashflowEngine.nextDays(accounts: Fix.accounts, streams: streams, transactions: [], now: now, calendar: Fix.calendar)
        #expect(days.count == 14 && days.first?.isToday == true)
        let rentDay = try! #require(days.first { $0.lines.contains { $0.name == "Rent" } })
        #expect(rentDay.balanceAfter == Fix.money("5") && !rentDay.isCrunch)     // 1455 − 1450
        let payday = try! #require(days.first { $0.hasIncome })
        #expect(payday.balanceAfter == Fix.money("2155"))
    }

    @Test func insightsRankCrunchFirstAndDropAcknowledged() {
        let verdict = Verdict(status: .headsUp,
                              ahead: Ahead(amount: -150, through: Fix.day(2026, 9, 26), crunch: Crunch(date: Fix.day(2026, 9, 22), shortfall: 150)),
                              kept: Kept(keptSoFar: 1800, expectedIncome: 4300, onPacePercent: 0.35))
        let pace = PaceEngine.pace(transactions: rows, streams: [], now: now, calendar: Fix.calendar)
        let netflix = RecurringStream(id: "netflix", merchant: "Netflix", kind: .subscription, cadence: .monthly, amount: Fix.money("17.99"), previousAmount: Fix.money("15.49"), lastSeen: Fix.day(2026, 8, 24), nextExpected: Fix.day(2026, 9, 24))
        var input = InsightEngine.Input(verdict: verdict, pace: pace, streams: [netflix], transactions: rows, now: now, calendar: Fix.calendar)
        let ranked = InsightEngine.rank(input)
        #expect(ranked.first?.kind == Insight.Kind.crunch)
        #expect(ranked.map(\.kind).contains(Insight.Kind.priceUp))
        #expect(ranked.map(\.kind).contains(Insight.Kind.positive))
        input.acknowledged = [ranked.first!.id]
        #expect(InsightEngine.rank(input).first?.kind != Insight.Kind.crunch)
    }

    @Test func weeklyReviewHasFiveCards() {
        let verdict = VerdictEngine.verdict(for: VerdictInput(accounts: Fix.accounts, transactions: rows, streams: [], now: now, expectedIncome: Fix.money("4300"), calendar: Fix.calendar))
        let pace = PaceEngine.pace(transactions: rows, streams: [], now: now, calendar: Fix.calendar)
        let insights = InsightEngine.rank(.init(verdict: verdict, pace: pace, streams: [], transactions: rows, now: now, calendar: Fix.calendar))
        let flow = CashflowEngine.nextDays(accounts: Fix.accounts, streams: [], transactions: [], now: now, calendar: Fix.calendar)
        let cards = WeeklyReview.cards(transactions: rows, streams: [], insights: insights, cashflow: flow, verdict: verdict, now: now, calendar: Fix.calendar)
        #expect(cards.count == 5 && cards[0].id == "kept" && cards[4].id == "positive")
        #expect(cards[1].title.hasPrefix("Groceries"))    // Trader Joe's $100 + Uber $50 this week → groceries biggest
    }
}
