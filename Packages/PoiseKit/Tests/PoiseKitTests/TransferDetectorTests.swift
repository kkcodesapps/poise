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
