import Foundation
import Testing
@testable import PoiseKit

/// A real order page, captured 2026-09-27, including the recommendation carousel that follows the order itself.
private let page = """
Order Details
Order placed September 22, 2026  Order # 113-6576175-6286635
View invoice
Ship to
Kolio Kolev
Payment method
Prime Visa••••9174
$76.49 (Earns 5% back) See terms and conditions
Order Summary
Item(s) Subtotal:
$74.99
Shipping & Handling:
$2.99
Free Shipping:
-$2.99
Total before tax:
$74.99
Estimated tax to be collected:
$1.50
Grand Total:
$76.49
Delivered September 22
Your package was left near the front door or porch.
NAKED Whey Isolate Protein - Only 2 Ingredients, 30g Grass-Fed Protein, Zero Carb, Unflavored - 28 Servings
Sold by: Naked Nutrition Inc
Return items: Eligible through October 22, 2026
$74.99
$74.99
Buy it again
View your item
Pick up where you left off
Page 1 of 18
Brabantia Bo Hi Touch Top Kitchen Trash Can with Dual Compartments & Raised Legs
4.1 out of 5 stars
$310.00
Sponsored
"""

@Suite("Amazon order detail") struct AmazonOrderDetailTests {

    @Test func readsWhatWasInTheOrder() {
        let detail = AmazonOrderDetails.parse(page, orderID: "113-6576175-6286635")
        #expect(detail.items.count == 1)
        #expect(detail.items[0].name.hasPrefix("NAKED Whey Isolate Protein"))
        #expect(detail.items[0].price == Fix.money("74.99"))
        #expect(detail.items[0].seller == "Naked Nutrition Inc")
    }

    @Test func readsTheTotals() {
        let detail = AmazonOrderDetails.parse(page, orderID: "113-6576175-6286635")
        #expect(detail.subtotal == Fix.money("74.99"))
        #expect(detail.tax == Fix.money("1.50"))
        #expect(detail.total == Fix.money("76.49"))
    }

    @Test func ignoresTheAdsUnderneath() {
        // Most of an order page is recommendations, with names and prices that look exactly like purchases.
        let detail = AmazonOrderDetails.parse(page, orderID: "113-6576175-6286635")
        #expect(!detail.items.contains { $0.name.contains("Brabantia") })
    }

    @Test func readsEveryLineOfAMultipleItemOrder() {
        let two = """
        Order Summary
        Grand Total:
        $88.98
        Delivered September 20
        Liquid I.V. Hydration Multiplier, Lemon Lime, 32 Sticks
        Sold by: Liquid I.V.
        Return items: Eligible through October 20, 2026
        $42.99
        Buy it again
        Anker 240W USB-C Cable, 2 Pack, Braided
        Sold by: AnkerDirect
        $25.99
        Buy it again
        """
        let detail = AmazonOrderDetails.parse(two, orderID: "113-0000000-0000000")
        #expect(detail.items.map(\.price) == [Fix.money("42.99"), Fix.money("25.99")])
        #expect(detail.items[1].seller == "AnkerDirect")
    }

    @Test func namesAreCutToSomethingSayable() {
        let detail = AmazonOrderDetails.parse(page, orderID: "113-6576175-6286635")
        // Amazon writes titles for search; the screen needs the part a person would actually say.
        #expect(detail.items[0].shortName == "NAKED Whey Isolate Protein")
    }

    @Test func anOrderPageWithNothingOnItIsNotAnError() {
        let detail = AmazonOrderDetails.parse("Sign in\nEmail or mobile phone number", orderID: "x")
        #expect(detail.items.isEmpty && detail.total == nil)
    }
}
