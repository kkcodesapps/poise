import Foundation
import Testing
@testable import PoiseKit

/// The page Amazon actually serves, trimmed to the shapes that matter: a card charge, a points charge, a refund,
/// an in-store purchase with an id nothing can open, and a digital order.
private let page = """
Completed
September 24, 2026
Prime Visa ****9174
-$209.18
Order #5766943f-c4d5-4482-8aea-bccb09337cb7
Whole Foods SCH 10276
September 23, 2026
Prime Visa ****9174
-$12.94
Order #113-5552522-7921812
Amazon.com
September 22, 2026
Prime Visa ****9174
-$14.99
Order #D01-8888414-4825832
D01-8888414-4825832
Amazon Visa points
-$94.14
Order #113-3689107-5559453
AMZN Mktp US
Prime Visa ****9174
-$76.49
Order #113-6576175-6286635
AMZN Mktp US
September 17, 2026
Prime Visa ****9174
+$43.29
Refund: Order #113-7658679-2849827
AMZN Mktp US
September 15, 2026
Prime Visa ****9174
-$1,247.53
Order #113-1302274-5982636
AMZN Mktp US
"""

@Suite("Amazon orders") struct AmazonOrderTests {

    @Test func readsTheOrdersOffThePaymentsPage() {
        let orders = AmazonOrders.parse(page, calendar: Fix.calendar)
        #expect(orders.map(\.id) == ["113-5552522-7921812", "113-3689107-5559453", "113-6576175-6286635",
                                     "113-7658679-2849827", "113-1302274-5982636"])
        let whey = orders[2]
        #expect(whey.amount == Fix.money("-76.49"))
        #expect(whey.date == Fix.calendar.startOfDay(for: Fix.day(2026, 9, 22)))
        #expect(whey.descriptor == "AMZN Mktp US")
        #expect(whey.url.absoluteString == "https://www.amazon.com/gp/css/order-details?orderID=113-6576175-6286635")
    }

    @Test func skipsWhatCannotBeOpened() {
        let orders = AmazonOrders.parse(page, calendar: Fix.calendar)
        // Whole Foods in store carries a UUID and Prime a D01 id: both are on the page, neither opens an order.
        #expect(!orders.contains { $0.id.contains("5766943f") || $0.id.hasPrefix("D01") })
    }

    @Test func aRefundKeepsItsSign() {
        let refund = AmazonOrders.parse(page, calendar: Fix.calendar).first { $0.id == "113-7658679-2849827" }
        #expect(refund?.amount == Fix.money("43.29"))
    }

    @Test func readsThousandsAndCommas() {
        let big = AmazonOrders.parse(page, calendar: Fix.calendar).first { $0.id == "113-1302274-5982636" }
        #expect(big?.amount == Fix.money("-1247.53"))
    }

    @Test func pairsAnOrderWithTheChargeThatPostedAfterIt() {
        let orders = AmazonOrders.parse(page, calendar: Fix.calendar)
        let charges = [
            Fix.tx("a", "card", "-76.49", "Amazon", on: Fix.day(2026, 9, 23)),          // posted the day after
            Fix.tx("b", "card", "-12.94", "Amazon", on: Fix.day(2026, 9, 24)),
            Fix.tx("c", "card", "43.29", "Amazon", on: Fix.day(2026, 9, 18), kind: .refund),
        ]
        let paired = AmazonOrders.match(orders, to: charges, calendar: Fix.calendar)
        #expect(paired["a"] == "113-6576175-6286635")
        #expect(paired["b"] == "113-5552522-7921812")
        #expect(paired["c"] == "113-7658679-2849827")
    }

    @Test func leavesAChargeAloneWhenNothingLinesUp() {
        let orders = AmazonOrders.parse(page, calendar: Fix.calendar)
        let charges = [
            Fix.tx("far", "card", "-76.49", "Amazon", on: Fix.day(2026, 8, 2)),         // same amount, six weeks off
            Fix.tx("other", "card", "-76.49", "Chipotle", on: Fix.day(2026, 9, 23)),    // right day, wrong merchant
            Fix.tx("cent", "card", "-76.50", "Amazon", on: Fix.day(2026, 9, 23)),       // a cent out
        ]
        #expect(AmazonOrders.match(orders, to: charges, calendar: Fix.calendar).isEmpty)
    }

    @Test func oneOrderCannotLandOnTwoCharges() {
        // Amazon splits an order across shipments, so the same amount really can appear twice in a week.
        let orders = AmazonOrders.parse(page, calendar: Fix.calendar)
        let charges = [
            Fix.tx("near", "card", "-76.49", "Amazon", on: Fix.day(2026, 9, 23)),
            Fix.tx("late", "card", "-76.49", "Amazon", on: Fix.day(2026, 9, 25)),
        ]
        let paired = AmazonOrders.match(orders, to: charges, calendar: Fix.calendar)
        #expect(paired.count == 1)
        #expect(paired["near"] == "113-6576175-6286635")            // the nearer charge takes it
    }

    @Test func readsThePhoneLayoutToo() {
        // The same list with the fields run together on one line, which is how Amazon renders it to a phone.
        let inline = """
        September 22, 2026
        Prime Visa ****9174 -$76.49 Order #113-6576175-6286635 AMZN Mktp US
        Prime Visa ****9174 +$24.89 Refund: Order #113-1783025-4076268 AMZN Mktp US
        """
        let orders = AmazonOrders.parse(inline, calendar: Fix.calendar)
        #expect(orders.count == 2)
        #expect(orders[0].id == "113-6576175-6286635" && orders[0].amount == Fix.money("-76.49"))
        #expect(orders[1].amount == Fix.money("24.89"))
        #expect(orders[0].date == Fix.calendar.startOfDay(for: Fix.day(2026, 9, 22)))
    }

    @Test func takesTheAmountAfterTheOrderWhenThatIsWhereItSits() {
        // Some renderings put the order first and the amount under it; the amount must still be the order's own.
        let flipped = """
        September 22, 2026
        Order #113-6576175-6286635
        -$76.49
        Order #113-5533759-6902604
        -$162.36
        """
        let orders = AmazonOrders.parse(flipped, calendar: Fix.calendar)
        #expect(orders.map(\.amount) == [Fix.money("-76.49"), Fix.money("-162.36")])
    }

    @Test func doesNotBorrowTheAmountOfANeighbouringCharge() {
        // An order with no amount anywhere near it is dropped rather than given the one next door.
        let orphan = """
        September 22, 2026
        -$76.49
        Order #113-6576175-6286635
        AMZN Mktp US
        September 21, 2026
        Order #113-5533759-6902604
        AMZN Mktp US
        September 20, 2026
        -$10.00
        """
        let orders = AmazonOrders.parse(orphan, calendar: Fix.calendar)
        #expect(orders.map(\.id) == ["113-6576175-6286635"])
    }

    @Test func aRefundedOrderMatchesBothItsChargeAndItsRefund() {
        // Taken from the live page: one order number listed twice, once as the charge and once as the refund.
        let both = """
        August 29, 2026
        Prime Visa ****9174
        -$24.89
        Order #113-1783025-4076268
        AMZN Mktp US
        September 17, 2026
        Prime Visa ****9174
        +$24.89
        Refund: Order #113-1783025-4076268
        AMZN Mktp US
        """
        let orders = AmazonOrders.parse(both, calendar: Fix.calendar)
        #expect(orders.count == 2)
        let rows = [
            Fix.tx("charge", "card", "-24.89", "Amazon", on: Fix.day(2026, 8, 30)),
            Fix.tx("refund", "card", "24.89", "Amazon", on: Fix.day(2026, 9, 18), kind: .refund),
        ]
        let paired = AmazonOrders.match(orders, to: rows, calendar: Fix.calendar)
        // Both sides belong to the same order and both should open it.
        #expect(paired["charge"] == "113-1783025-4076268")
        #expect(paired["refund"] == "113-1783025-4076268")
    }

    @Test func matchesWhenTheBankAuthorisedDaysBeforeAmazonCharged() {
        // Amazon charges when it ships; the bank authorised when the order was placed, two days earlier.
        let page = """
        September 14, 2026
        Prime Visa ****9174
        -$99.48
        Order #113-0062732-9348242
        AMZN Mktp US
        """
        let orders = AmazonOrders.parse(page, calendar: Fix.calendar)
        let charge = Fix.tx("c", "card", "-99.48", "Amazon", on: Fix.day(2026, 9, 14), authorized: Fix.day(2026, 9, 12))
        #expect(AmazonOrders.match(orders, to: [charge], calendar: Fix.calendar)["c"] == "113-0062732-9348242")
    }

    @Test func aPageOfNothingIsNotAnError() {
        #expect(AmazonOrders.parse("", calendar: Fix.calendar).isEmpty)
        #expect(AmazonOrders.parse("Sign in\nEmail or mobile phone number", calendar: Fix.calendar).isEmpty)
    }
}
