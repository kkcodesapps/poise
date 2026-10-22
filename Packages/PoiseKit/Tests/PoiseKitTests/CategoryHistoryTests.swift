import Foundation
import Testing
@testable import PoiseKit

struct CategoryHistoryTests {
    let now = Fix.day(2026, 9, 20)

    /// One grocery charge a month, with the amounts given per month from the date given.
    func monthly(_ id: String, _ merchant: String, from: (Int, Int), _ amounts: [String], category: SpendCategory = .groceries) -> [PoiseKit.Transaction] {
        amounts.enumerated().compactMap { i, a in
            guard a != "-", let d = Fix.calendar.date(byAdding: .month, value: i, to: Fix.day(from.0, from.1, 12)) else { return nil }
            return Fix.tx("\(id)\(i)", "card", "-\(a)", merchant, on: d, category: category)
        }
    }

    @Test func aMonthRunAgainstTheUsualOne() {
        // Ten months of groceries; the last is the month in view and runs high.
        let rows = monthly("g", "Whole Foods", from: (2025, 12), ["200", "210", "190", "205", "0", "215", "195", "205", "200", "400"])
        let h = try! #require(CategoryHistoryEngine.history(categoryID: "groceries", transactions: rows, now: now, calendar: Fix.calendar))
        #expect(h.months.count == 10 && h.months.first?.start == Fix.calendar.dateInterval(of: .month, for: Fix.day(2025, 12, 1))?.start)
        #expect(h.current.total == Fix.money("400") && h.usual == Fix.money("205"))   // median of the earlier months that had charges
        #expect(h.lastYear == nil && h.delta == Fix.money("195"))                      // no September a year ago yet
        #expect(h.ranges.isEmpty)                                                       // under a year: nothing to pick between
        let ins = try! #require(CategoryHistoryEngine.overspendInsight(categoryID: "groceries", name: "Groceries", history: h, now: now, calendar: Fix.calendar))
        #expect(ins.kind == Insight.Kind.categoryOver && ins.title == "Groceries is $195 over" && ins.body.contains("than a usual month"))
    }

    @Test func threeYearsComparesTheSameMonthLastYear() {
        // 36 months ending in the month in view; last September was $300, this one is $250.
        var amounts = Array(repeating: "220", count: 36)
        amounts[23] = "300"    // Sep 2025 (index 23 from Oct 2023)
        amounts[35] = "250"    // Sep 2026
        let rows = monthly("g", "Whole Foods", from: (2023, 10), amounts)
        let h = try! #require(CategoryHistoryEngine.history(categoryID: "groceries", transactions: rows, now: now, calendar: Fix.calendar))
        #expect(h.months.count == 36 && h.years == 2)
        #expect(h.comparedToLastYear && h.lastYear?.total == Fix.money("300"))
        #expect(h.delta == Fix.money("-50"))                                            // measured against last September, not the usual
        #expect(h.ranges == [.year, .twoYears, .all])
        #expect(h.months(in: .year).count == 12 && h.months(in: .twoYears).count == 24 && h.months(in: .all).count == 36)
        #expect(CategoryHistoryEngine.overspendInsight(categoryID: "groceries", name: "Groceries", history: h, now: now, calendar: Fix.calendar) == nil)
    }

    @Test func whatMovedNamesTheMerchantsBehindIt() {
        // Last September: Instacart $100, Whole Foods $200. This September: Instacart $500, Whole Foods $200, Aldi $120.
        var rows = monthly("w", "Whole Foods", from: (2025, 9), Array(repeating: "200", count: 13))
        rows += [Fix.tx("i0", "card", "-100", "Instacart", on: Fix.day(2025, 9, 14), category: .groceries),
                 Fix.tx("i1", "card", "-500", "Instacart", on: Fix.day(2026, 9, 14), category: .groceries),
                 Fix.tx("a1", "card", "-120", "Aldi", on: Fix.day(2026, 9, 16), category: .groceries),
                 Fix.tx("t0", "card", "-90", "Target", on: Fix.day(2025, 9, 18), category: .groceries)]
        let h = try! #require(CategoryHistoryEngine.history(categoryID: "groceries", transactions: rows, now: now, calendar: Fix.calendar))
        #expect(h.comparedToLastYear)
        let names = h.moves.map(\.name)
        #expect(names.contains("Instacart") && names.contains("Aldi") && names.contains("Target"))
        let instacart = try! #require(h.moves.first { $0.name == "Instacart" })
        #expect(instacart.delta == Fix.money("400") && instacart.was == Fix.money("100") && !instacart.isNew)
        let aldi = try! #require(h.moves.first { $0.name == "Aldi" })
        #expect(aldi.isNew && aldi.delta == Fix.money("120"))
        let gone = try! #require(h.moves.first { $0.name == "Target" })
        #expect(gone.amount == 0 && gone.delta == Fix.money("-90"))                      // stopped is movement too
        #expect(!names.contains("Whole Foods"))                                          // steady merchants stay out of the way
    }
}
