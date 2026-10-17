import Foundation
import Testing
@testable import PoiseKit

struct PriceTests {
    let now = Fix.day(2026, 9, 20)

    func amazon(_ id: String, _ price: String, _ m: Int, _ d: Int, name: String? = "Naked Whey Protein", pending: Bool = false) -> PoiseKit.Transaction {
        var t = Fix.tx(id, "visa", "-\(price)", "AMAZON.COM*2K4PL9", on: Fix.day(2026, m, d), pending: pending, category: .shopping)
        t.displayName = name
        return t
    }

    @Test func namedChargesBecomeAnItemWithItsPriceRun() {
        let rows = [amazon("p1", "29.99", 2, 3), amazon("p2", "29.99", 3, 9), amazon("p3", "27.49", 4, 20), amazon("p4", "29.99", 6, 1),
                    amazon("p5", "29.99", 7, 14), amazon("p6", "34.99", 8, 12), amazon("p7", "34.99", 9, 19, pending: true),
                    Fix.tx("x1", "visa", "-142.79", "AMAZON.COM*9QZ", on: Fix.day(2026, 9, 17), category: .shopping)]   // an unnamed Amazon order stays out
        let items = PriceTracker.items(in: rows, now: now, calendar: Fix.calendar)
        let whey = try! #require(items.first { $0.id == "named|naked whey protein" })
        #expect(whey.count == 7 && whey.last == Fix.money("34.99") && whey.usual == Fix.money("29.99") && whey.lowest == Fix.money("27.49") && whey.highest == Fix.money("34.99"))
        #expect(whey.previous == Fix.money("29.99") && whey.changedAt == Fix.day(2026, 8, 12))
        #expect(whey.direction == PriceItem.Direction.up && whey.movedLately(now: now, calendar: Fix.calendar))
        #expect(abs(whey.deltaPercent - 0.1667) < 0.001)
        #expect(!items.contains { $0.source == .merchant && $0.merchantKey == "amazoncom" })   // one unnamed order isn't a run
    }

    @Test func steadyMerchantsGetAUsualPriceAndVariedOnesARange() {
        let chipotle = (0..<6).map { Fix.tx("c\($0)", "card", $0 == 5 ? "-16.20" : "-14.20", "Chipotle", on: Fix.day(2026, 4 + $0, 10), category: .dining) }
        let wholeFoods = [("206.55", 5), ("243.02", 6), ("92.10", 7), ("310.40", 8)].enumerated().map { i, p in Fix.tx("w\(i)", "card", "-\(p.0)", "Whole Foods", on: Fix.day(2026, p.1, 3), category: .groceries) }
        let items = PriceTracker.items(in: chipotle + wholeFoods, now: now, calendar: Fix.calendar)
        #expect(Set(items.map(\.id)) == ["merchant|chipotle", "merchant|whole foods"])
        let burrito = try! #require(items.first { $0.id == "merchant|chipotle" }), groceries = try! #require(items.first { $0.id == "merchant|whole foods" })
        #expect(burrito.steady && burrito.usual == Fix.money("14.20") && burrito.last == Fix.money("16.20") && burrito.direction == PriceItem.Direction.up)
        #expect(!groceries.steady && groceries.direction == PriceItem.Direction.steady && groceries.lowest == Fix.money("92.10") && groceries.highest == Fix.money("310.40"))
        // A move needs 3 % and fifty cents; a cent isn't news.
        #expect(!PriceTracker.moved(Fix.money("14.21"), from: Fix.money("14.20")) && PriceTracker.moved(Fix.money("16.20"), from: Fix.money("14.20")))
    }

    @Test func aPlanIsItsOwnRunAndTheRestIsUsage() {
        // Cursor: $200 on the 19th every month, plus pay-as-you-go charges in between.
        var rows = (0..<4).map { Fix.tx("plan\($0)", "card", "-200", "Cursor", on: Fix.day(2026, 6 + $0, 19), category: .subscriptions) }
        rows += [("63.20", 8, 18), ("80.15", 8, 22), ("100.05", 9, 14), ("100.27", 9, 16)].enumerated().map { i, u in Fix.tx("use\(i)", "card", "-\(u.0)", "Cursor", on: Fix.day(2026, u.1, u.2), category: .subscriptions) }
        let streams = RecurringDetector.detect(rows, now: now, calendar: Fix.calendar)
        let items = PriceTracker.items(in: rows, streams: streams, now: now, calendar: Fix.calendar)
        let plan = try! #require(items.first { $0.source == .plan }), usage = try! #require(items.first { $0.source == .merchant })
        #expect(plan.id == "plan|spend|cursor" && plan.planSuffix == "plan" && plan.count == 4 && plan.usual == Fix.money("200") && plan.steady)
        #expect(usage.planSuffix == "usage" && usage.count == 4 && usage.streamID == "spend|cursor")
    }

    @Test func trackedItemsRaiseAnInsightForAFreshMove() {
        var whey = PriceTracker.items(in: [amazon("p1", "29.99", 6, 1), amazon("p2", "29.99", 7, 14), amazon("p3", "34.99", 9, 18)], now: now, calendar: Fix.calendar)[0]
        #expect(PriceTracker.insights([whey], now: now, calendar: Fix.calendar).isEmpty)   // not tracked
        whey.tracked = true
        let ins = try! #require(PriceTracker.insights([whey], now: now, calendar: Fix.calendar).first)
        #expect(ins.kind == Insight.Kind.priceMoved && ins.title == "Naked Whey Protein · $34.99, usually $29.99")
        #expect(ins.body.hasPrefix("Up $5.00 since September — 17% more"))
    }
}
