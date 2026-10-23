import Foundation
import Testing
@testable import PoiseKit

struct TransferDetectorTests {
    @Test func pairsMoveToSavingsAsTransfer() {
        let rows = [
            Fix.tx("a", "chk", "-300", "Online transfer", on: Fix.day(2026, 9, 11)),
            Fix.tx("b", "sav", "300", "Transfer in", on: Fix.day(2026, 9, 12)),
            Fix.tx("c", "chk", "-62.40", "Costco", on: Fix.day(2026, 9, 12), category: .groceries),
        ]
        let out = TransferDetector.pair(rows, accounts: Fix.accounts, calendar: Fix.calendar)
        #expect(out[0].kind == TransactionKind.transfer && out[0].pairID == "b")
        #expect(out[1].kind == TransactionKind.transfer && out[1].pairID == "a")
        #expect(out[2].kind == TransactionKind.spend && out[2].pairID == nil)
    }

    @Test func paymentToCreditCardIsNotSpend() {
        let rows = [
            Fix.tx("pay", "chk", "-612.40", "Chase card payment", on: Fix.day(2026, 9, 5)),
            Fix.tx("recv", "card", "612.40", "Payment thank you", on: Fix.day(2026, 9, 6)),
        ]
        let out = TransferDetector.pair(rows, accounts: Fix.accounts, calendar: Fix.calendar)
        #expect(out.allSatisfy { $0.kind == TransactionKind.ccPayment })
    }

    @Test func outsideWindowStaysUnpaired() {
        let rows = [
            Fix.tx("a", "chk", "-300", "Online transfer", on: Fix.day(2026, 9, 1)),
            Fix.tx("b", "sav", "300", "Transfer in", on: Fix.day(2026, 9, 9)),
        ]
        let out = TransferDetector.pair(rows, accounts: Fix.accounts, calendar: Fix.calendar)
        #expect(out.allSatisfy { $0.pairID == nil })
    }
}

@Suite("One row per movement") struct CollapsedFeedTests {

    /// The real shape: Chase shows the money leaving on the 28th, Apple Card shows it arriving on the 27th.
    private var bothLegs: [Transaction] {
        TransferDetector.pair([
            Fix.tx("chase", "chk", "-3694.79", "Apple Card", on: Fix.day(2026, 9, 28)),
            Fix.tx("card", "card", "3694.79", "Bill Payment", on: Fix.day(2026, 9, 27)),
        ], accounts: Fix.accounts, calendar: Fix.calendar)
    }

    @Test func aCardPaymentIsOneRowNotTwo() {
        let feed = TransferDetector.collapsed(bothLegs)
        #expect(feed.map(\.id) == ["chase"])                       // the money leaving is what happened
    }

    @Test func theEnginesStillSeeBothHalves() {
        // The card's statement balance depends on the payment landing on it, so nothing is removed from the real list.
        #expect(bothLegs.count == 2)
        #expect(bothLegs.allSatisfy { $0.kind == .ccPayment && $0.pairID != nil })
    }

    @Test func aPaymentToACardPoiseCannotSeeStays() {
        // Only one side is linked, so there's nothing to collapse and the row must survive.
        let lonely = [Fix.tx("only", "chk", "-500.00", "Amex", on: Fix.day(2026, 9, 28), kind: .ccPayment)]
        #expect(TransferDetector.collapsed(lonely).map(\.id) == ["only"])
    }

    @Test func moneyMovedIntoSavingsAlsoShowsOnce() {
        let moved = TransferDetector.pair([
            Fix.tx("out", "chk", "-300.00", "To Ally Savings", on: Fix.day(2026, 9, 28)),
            Fix.tx("in", "sav", "300.00", "Transfer", on: Fix.day(2026, 9, 28)),
        ], accounts: Fix.accounts, calendar: Fix.calendar)
        #expect(TransferDetector.collapsed(moved).map(\.id) == ["out"])
    }
}
