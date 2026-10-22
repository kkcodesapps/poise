import Foundation
import Testing
@testable import PoiseKit

struct WhereAndWatchTests {
    let now = Fix.day(2026, 9, 15)   // Tuesday

    var rows: [PoiseKit.Transaction] {
        [
            Fix.tx("a", "card", "-200", "DoorDash", on: Fix.day(2026, 9, 3), category: .dining),
            Fix.tx("b", "card", "-100", "Trader Joe's", on: Fix.day(2026, 9, 10), category: .groceries),
            Fix.tx("c", "card", "-50", "Uber", on: Fix.day(2026, 9, 12), category: .transport),
            Transaction(id: "r", accountID: "card", amount: Fix.money("20"), merchant: "DoorDash", date: Fix.day(2026, 9, 13), kind: .refund, category: .dining, pairID: "a"),
            Fix.tx("d", "card", "-100", "DoorDash", on: Fix.day(2026, 8, 5), category: .dining),
            Fix.tx("e", "card", "-150", "Trader Joe's", on: Fix.day(2026, 8, 20), category: .groceries),
            Fix.tx("k", "chk", "-300", "Kids 529", on: Fix.day(2026, 9, 4), categoryID: "kids-savings"),
        ]
    }

    @Test func periodsAreMondayFirst() {
        let week = Periods.window(.week, containing: now, calendar: Fix.calendar)
        #expect(Fix.calendar.component(.weekday, from: week.start) == 2)            // Monday Sep 14
        #expect(Periods.slices(week, .week, calendar: Fix.calendar).count == 7)
        let month = Periods.window(.month, containing: now, calendar: Fix.calendar)
        let slices = Periods.slices(month, .month, calendar: Fix.calendar)
        #expect(slices.count == 5 && slices[0].label == "1–7" && slices[4].label == "29–30")
        #expect(Periods.slices(Periods.window(.year, containing: now, calendar: Fix.calendar), .year, calendar: Fix.calendar).count == 12)
        #expect(Periods.title(month, .month, calendar: Fix.calendar) == "September")
    }

    @Test func aWindowIsMeasuredAgainstTheWholePeriodBefore() {
        // September, mid-month, compares against all of August — the plain reading of "vs Aug".
        let month = Periods.window(.month, containing: now, calendar: Fix.calendar)
        let prev = Periods.comparable(previousOf: month, .month, calendar: Fix.calendar)
        #expect(Fix.calendar.component(.month, from: prev.start) == 8 && Fix.calendar.component(.day, from: prev.start) == 1)
        #expect(prev.end == Fix.calendar.dateInterval(of: .month, for: Fix.day(2026, 8, 10))?.end)
    }

    @Test func theComparisonLabelNamesTheWholePreviousPeriod() {
        let month = Periods.window(.month, containing: now, calendar: Fix.calendar)
        #expect(Periods.shortPreviousLabel(month, .month, calendar: Fix.calendar) == "vs Aug")
        #expect(Periods.previousLabel(.month) == "last month")
        let august = Periods.window(.month, containing: Fix.day(2026, 8, 10), calendar: Fix.calendar)
        #expect(Periods.shortPreviousLabel(august, .month, calendar: Fix.calendar) == "vs Jul")
    }

    @Test func breakdownRanksAndNetsRefunds() {
        let kids = Category(id: "kids-savings", name: "Kids savings", symbol: "person", lens: .kept, builtIn: false, sort: 0)
        let cats = CategorySet([kids])
        let month = Periods.window(.month, containing: now, calendar: Fix.calendar)
        let b = CategoryBreakdown.compute(transactions: rows, period: .month, window: month, now: now, categories: cats, calendar: Fix.calendar)
        #expect(b.total == Fix.money("330"))                                          // 200 − 20 + 100 + 50; the kept-lens $300 is not spend
        #expect(b.rows.map(\.categoryID) == ["dining", "groceries", "transport"])
        #expect(b.rows[0].amount == Fix.money("180") && b.rows[0].count == 1)
        #expect(b.rows[0].delta == Fix.money("80"))                                    // vs $100 in August
        #expect(b.rows[2].delta == nil)                                                // Uber is new
        #expect(b.slices.count == 5 && b.slices[1].amount == Fix.money("130") && b.slices[1].transactions.count == 3)   // Sep 8–14: TJ 100 + Uber 50 − refund 20
        #expect(abs(b.rows[0].share - 180.0 / 330.0) < 0.001)
        let m = CategoryBreakdown.merchants(in: "dining", transactions: rows, window: month, categories: cats)
        #expect(m.first?.name == "DoorDash" && m.first?.count == 1)
    }

    @Test func midnightRowsLandInOneDayOnly() {
        // Provider rows are dated at local midnight; a Friday charge must not also count as Thursday's.
        let week = Periods.window(.week, containing: Fix.day(2026, 9, 18), calendar: Fix.calendar)
        let two = [Fix.tx("th", "card", "-10", "JuRin Sushi", on: Fix.day(2026, 9, 17)), Fix.tx("fr", "card", "-20", "sweetgreen", on: Fix.day(2026, 9, 18))]
        let b = CategoryBreakdown.compute(transactions: two, period: .week, window: week, now: Fix.day(2026, 9, 18), categories: CategorySet([]), calendar: Fix.calendar)
        let thursday = b.slices[3], friday = b.slices[4]
        #expect(thursday.transactions.map(\.id) == ["th"] && thursday.amount == Fix.money("10"))
        #expect(friday.transactions.map(\.id) == ["fr"] && friday.amount == Fix.money("20"))
        #expect(b.total == Fix.money("30"))
    }

    @Test func refundWatchResolvesAndOverdues() {
        let w = Watch(id: "w1", kind: .refund, transactionID: "a", merchant: "DoorDash", expectedAmount: Fix.money("20"), nudgeDays: 5, createdAt: Fix.day(2026, 9, 3))
        let evaluated = WatchEngine.evaluate([w], transactions: rows, now: now, calendar: Fix.calendar)
        #expect(evaluated[0].status == Watch.Status.arrived && evaluated[0].resolvedTransactionID == "r")
        let bigger = Watch(id: "w2", kind: .refund, transactionID: "a", merchant: "DoorDash", expectedAmount: Fix.money("200"), nudgeDays: 5, createdAt: Fix.day(2026, 9, 3))
        let e2 = WatchEngine.evaluate([bigger], transactions: rows, now: now, calendar: Fix.calendar)
        #expect(e2[0].status == Watch.Status.overdue)                                   // $20 back isn't $200, and it's been 12 days
        let ins = WatchEngine.insights(e2 + evaluated, transactions: rows, now: now, calendar: Fix.calendar)
        #expect(ins.contains { $0.kind == .refundOverdue } && ins.contains { $0.kind == .refundArrived })
    }

    @Test func merchantWatchTriggersOnTheNextCharge() {
        let w = Watch(id: "m1", kind: .merchant, transactionID: "d", merchant: "DoorDash", createdAt: Fix.day(2026, 8, 6))
        let e = WatchEngine.evaluate([w], transactions: rows, now: now, calendar: Fix.calendar)
        #expect(e[0].status == Watch.Status.triggered && e[0].resolvedTransactionID == "a")
        #expect(WatchEngine.insights(e, transactions: rows, now: now, calendar: Fix.calendar).first?.rank == 2)
        let quiet = Watch(id: "m2", kind: .merchant, merchant: "Kumon", createdAt: Fix.day(2026, 8, 6))
        #expect(WatchEngine.evaluate([quiet], transactions: rows, now: now, calendar: Fix.calendar)[0].status == Watch.Status.watching)
    }
}
