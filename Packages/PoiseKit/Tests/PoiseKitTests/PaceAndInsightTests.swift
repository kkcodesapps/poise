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
        #expect(pace.movers.first?.categoryID == "dining" && pace.movers.first?.delta == Fix.money("100"))
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

    @Test func cardSubscriptionsShowButDontDrainChecking() {
        var card = Fix.card; card.statementDue = Fix.day(2026, 9, 25); card.statementAmount = Fix.money("612.40")
        let spotify = RecurringStream(id: "spend|spotify", merchant: "Spotify", kind: .subscription, cadence: .monthly, amount: Fix.money("12.99"), lastSeen: Fix.day(2026, 8, 20), nextExpected: Fix.day(2026, 9, 20), accountID: "card")
        let rent = RecurringStream(id: "spend|rent", merchant: "Rent", kind: .bill, cadence: .monthly, amount: Fix.money("1450"), lastSeen: Fix.day(2026, 8, 22), nextExpected: Fix.day(2026, 9, 22), accountID: "chk")
        let days = CashflowEngine.nextDays(accounts: [Fix.checking, card], streams: [spotify, rent], transactions: [], now: Fix.day(2026, 9, 15), calendar: Fix.calendar)
        let sep20 = try! #require(days.first { Fix.calendar.component(.day, from: $0.date) == 20 })
        #expect(sep20.lines.first?.viaCard == "Sapphire" && sep20.cashMoved == 0 && sep20.balanceAfter == Fix.money("1455"))      // shown, not subtracted
        let sep22 = try! #require(days.first { Fix.calendar.component(.day, from: $0.date) == 22 })
        #expect(sep22.balanceAfter == Fix.money("5"))                                                                                // rent leaves checking
        let sep25 = try! #require(days.first { Fix.calendar.component(.day, from: $0.date) == 25 })
        #expect(sep25.balanceAfter == Fix.money("-607.40"))                                                                          // the statement does too
    }

    @Test func aPendingCardPaymentReadsAsMoneyLeaving() {
        // Robinhood signs the payment positive on the card; the same movement leaves checking. One line, negative, no payday.
        let today = Fix.day(2026, 9, 22)
        var card = Fix.card, chk = Fix.checking
        let onCard = Transaction(id: "p-card", accountID: card.id, amount: Fix.money("2956.87"), merchant: "Payment", date: today, pending: true, kind: .ccPayment, pairID: "pay1")
        let fromCash = Transaction(id: "p-cash", accountID: chk.id, amount: Fix.money("-2956.87"), merchant: "Payment", date: today, pending: true, kind: .ccPayment, pairID: "pay1")
        let days = CashflowEngine.nextDays(accounts: [chk, card], streams: [], transactions: [onCard, fromCash], now: today, calendar: Fix.calendar)
        let first = days[0]
        #expect(first.lines.count == 1 && first.lines[0].amount == Fix.money("-2956.87") && !first.hasIncome)
        // The same pair without the provider linking them: matched on the amount and the day instead.
        var loose = onCard; loose.pairID = nil
        var looseCash = fromCash; looseCash.pairID = nil
        let unpaired = CashflowEngine.nextDays(accounts: [chk, card], streams: [], transactions: [loose, looseCash], now: today, calendar: Fix.calendar)
        #expect(unpaired[0].lines.map(\.amount) == [Fix.money("-2956.87")])
        // A card with no linked checking still reads as money out, not in.
        let alone = CashflowEngine.nextDays(accounts: [card], streams: [], transactions: [onCard], now: today, calendar: Fix.calendar)
        #expect(alone[0].lines.map(\.amount) == [Fix.money("-2956.87")] && !alone[0].hasIncome)
    }

    @Test func appleCardStatementIsRebuiltFromPostedRows() {
        // Due Sep 30 → the August cycle. Charges add, the refund subtracts, the Aug 27 payment is before the close (it paid
        // July's statement), pending rows don't count yet, and September's charges belong to the next statement.
        var card = Account(id: "apple", name: "Apple Card", role: .credit, current: Fix.money("6238.35"))
        card.statementDue = Fix.day(2026, 9, 30); card.minimumDue = Fix.money("73.62")
        let rows = [
            Fix.tx("a1", "apple", "-3500.00", "Costco", on: Fix.day(2026, 8, 12)),
            Fix.tx("a2", "apple", "-213.18", "Target", on: Fix.day(2026, 8, 20)),
            Fix.tx("a3", "apple", "18.39", "Target", on: Fix.day(2026, 8, 7), kind: .refund),
            Fix.tx("a4", "apple", "7970.00", "Bill Payment", on: Fix.day(2026, 8, 27), kind: .ccPayment),
            Fix.tx("a5", "apple", "-2104.00", "Amazon", on: Fix.day(2026, 9, 10)),
            Fix.tx("a6", "apple", "-50.00", "Shell", on: Fix.day(2026, 8, 30), pending: true),
        ]
        #expect(StatementEstimator.statement(for: card, transactions: rows, calendar: Fix.calendar) == Fix.money("3694.79"))
        // A payment after the close comes off what's still owed on it.
        let paid = rows + [Fix.tx("a7", "apple", "1000.00", "Bill Payment", on: Fix.day(2026, 9, 5), kind: .ccPayment)]
        #expect(StatementEstimator.statement(for: card, transactions: paid, calendar: Fix.calendar) == Fix.money("2694.79"))
        // No rows from that month at all → no guess.
        #expect(StatementEstimator.statement(for: card, transactions: [rows[4]], calendar: Fix.calendar) == nil)
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

@Suite("A card's payment stays in the forecast") struct StaleDueDateTests {
    private let now = Fix.day(2026, 10, 9)

    private func card(due: Date?, statement: String? = "500.00") -> Account {
        Account(id: "c", name: "Prime Visa", mask: "9174", role: .credit, current: Fix.money("-2000"),
                statementDue: due, statementAmount: statement.map(Fix.money), minimumDue: Fix.money("40"))
    }

    @Test func aDueDateStillAheadIsUsedAsIs() {
        let next = card(due: Fix.day(2026, 10, 22)).nextDue(now: now, calendar: Fix.calendar)
        #expect(next?.date == Fix.day(2026, 10, 22))
        #expect(next?.isEstimate == false)
    }

    @Test func aDueDateThatHasPassedRollsToTheNextMonth() {
        // The real case: the provider still reports Sep 30 on Oct 9, so the payment was dropped from the forecast.
        let next = card(due: Fix.day(2026, 9, 30)).nextDue(now: now, calendar: Fix.calendar)
        #expect(Fix.calendar.component(.month, from: next!.date) == 10)
        #expect(Fix.calendar.component(.day, from: next!.date) == 30)
        #expect(next?.isEstimate == true)
    }

    @Test func aVeryStaleDateRollsAsFarAsItNeeds() {
        let next = card(due: Fix.day(2026, 6, 15)).nextDue(now: now, calendar: Fix.calendar)
        #expect(next!.date > now)
        #expect(Fix.calendar.component(.month, from: next!.date) == 10)
    }

    @Test func todayIsNotTreatedAsStillToCome() {
        // Due today is already in the balance or already missed; either way the next one is a month out.
        let next = card(due: Fix.day(2026, 10, 9)).nextDue(now: now, calendar: Fix.calendar)
        #expect(Fix.calendar.component(.month, from: next!.date) == 11)
    }

    @Test func aCardWithNoDueDateAtAllStaysOut() {
        #expect(card(due: nil).nextDue(now: now, calendar: Fix.calendar) == nil)
    }

    @Test func theRolledPaymentActuallyReachesTheForecast() {
        let stale = card(due: Fix.day(2026, 9, 30))
        let days = CashflowEngine.nextDays(30, accounts: [Fix.checking, stale], streams: [], transactions: [],
                                           now: now, calendar: Fix.calendar)
        let line = days.flatMap(\.lines).first { $0.name.contains("Prime Visa") }
        #expect(line?.amount == Fix.money("-500"))
        #expect(line?.name.contains("estimated") == true)      // said out loud, not passed off as the bank's own date
    }
}

@Suite("How a card is paid") struct CardPaymentTests {
    private let now = Fix.day(2026, 10, 9)

    /// The real shape of the Prime Visa: a statement that closed at $4,020.25 and $2,292.48 charged since.
    private func visa(_ pays: CardPayment?, fixed: String? = nil) -> Account {
        Account(id: "visa", name: "Prime Visa", mask: "9174", role: .credit, current: Fix.money("6312.73"),
                statementDue: Fix.day(2026, 10, 22), statementAmount: Fix.money("4020.25"), minimumDue: Fix.money("40"),
                pays: pays, paysFixedAmount: fixed.map(Fix.money))
    }

    @Test func theStatementBalanceIsWhatClosed() {
        #expect(visa(.statement).statementPayment() == Fix.money("4020.25"))
    }

    @Test func theWholeBalanceIncludesWhatHasBeenSpentSince() {
        // $2,292.48 more than the statement — the difference this choice exists for.
        #expect(visa(.full).statementPayment() == Fix.money("6312.73"))
    }

    @Test func theMinimumIsTheMinimum() {
        #expect(visa(.minimum).statementPayment() == Fix.money("40"))
    }

    @Test func aSetAmountIsUsedAsGiven() {
        #expect(visa(.fixed, fixed: "500").statementPayment() == Fix.money("500"))
        #expect(visa(.fixed).statementPayment() == nil)          // nothing entered yet: nothing claimed
    }

    @Test func aCardTheUserHasNotDecidedAboutFollowsTheDefault() {
        #expect(visa(nil).statementPayment(default: .minimum) == Fix.money("40"))
        #expect(visa(nil).statementPayment(default: .statement) == Fix.money("4020.25"))
        // And a card that has decided ignores the default entirely.
        #expect(visa(.minimum).statementPayment(default: .full) == Fix.money("40"))
    }

    @Test func theWholeBalanceIsTheDebtNotTheCreditLeft() {
        // Caught on a real screen: a card owing $1,284 against a $12,000 limit reports $10,715 *available*, and
        // "the whole balance" offered to pay that off.
        let card = Account(id: "a", name: "Apple Card", role: .credit, available: Fix.money("10715.84"),
                           current: Fix.money("1284.16"), statementDue: Fix.day(2026, 10, 30),
                           minimumDue: Fix.money("25"), pays: .full)
        #expect(card.statementPayment() == Fix.money("1284.16"))
    }

    @Test func aCardReportedNegativeIsReadTheSameWay() {
        // Providers disagree on the sign of what's owed; the forecast must not.
        let negative = Account(id: "n", name: "Card", role: .credit, current: Fix.money("-6312.73"),
                               statementDue: Fix.day(2026, 10, 22), minimumDue: Fix.money("40"), pays: .full)
        #expect(negative.statementPayment() == Fix.money("6312.73"))
    }

    @Test func eachCardIsForecastItsOwnWay() {
        // Two cards, two choices, both in the same fortnight — the thing one global toggle couldn't express.
        let apple = Account(id: "apple", name: "Apple Card", role: .credit, current: Fix.money("6612.11"),
                            statementDue: Fix.day(2026, 10, 16), minimumDue: Fix.money("67.62"), pays: .minimum)
        let days = CashflowEngine.nextDays(30, accounts: [Fix.checking, visa(.statement), apple],
                                           streams: [], transactions: [], now: now, calendar: Fix.calendar)
        let lines = days.flatMap(\.lines)
        #expect(lines.first { $0.name.contains("Prime Visa") }?.amount == Fix.money("-4020.25"))
        #expect(lines.first { $0.name.contains("Apple Card") }?.amount == Fix.money("-67.62"))
    }
}
