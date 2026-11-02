import Foundation
import Testing
@testable import PoiseKit

/// Subscription or bill is decided by what the merchant is, never by the category it's filed under.
struct StreamKindTests {
    func charge(_ merchant: String, category: SpendCategory? = nil, categoryID: String? = nil, provider: String?) -> Transaction {
        var t = Fix.tx("x", "card", "-24.99", merchant, on: Fix.day(2026, 9, 17), category: category, categoryID: categoryID)
        t.providerCategory = provider
        return t
    }

    @Test func aGymIsHealthAndASubscription() {
        let gym = charge("Planet Fitness", category: .health, provider: "PERSONAL_CARE_GYMS_AND_FITNESS_CENTERS")
        #expect(RecurringDetector.streamKind(for: gym, categories: .builtIn) == .subscription)
    }

    @Test func utilitiesPhoneInsuranceAndLoansAreBills() {
        for p in ["RENT_AND_UTILITIES_TELEPHONE", "RENT_AND_UTILITIES_GAS_AND_ELECTRICITY", "GENERAL_SERVICES_INSURANCE", "LOAN_PAYMENTS_CAR_PAYMENT"] {
            // Filed under a custom "Car" category with a needs lens, or anything else: still a bill.
            #expect(RecurringDetector.streamKind(for: charge("Payee", categoryID: "car-uuid", provider: p), categories: .builtIn) == .bill)
        }
    }

    @Test func streamingIsASubscriptionWhateverItsFiledUnder() {
        let netflix = charge("Netflix", category: .entertainment, provider: "ENTERTAINMENT_TV_AND_MOVIES")
        let icloud = charge("Apple", category: .tech, provider: "ENTERTAINMENT_MUSIC_AND_AUDIO")
        #expect(RecurringDetector.streamKind(for: netflix, categories: .builtIn) == .subscription)
        #expect(RecurringDetector.streamKind(for: icloud, categories: .builtIn) == .subscription)
    }

    @Test func withoutTheProvidersWordHomeIsABill() {
        #expect(RecurringDetector.streamKind(for: charge("Landlord", category: .home, provider: nil), categories: .builtIn) == .bill)
        #expect(RecurringDetector.streamKind(for: charge("Gym", category: .health, provider: nil), categories: .builtIn) == .subscription)
    }

    @Test func theOldSubscriptionsCategoryReadsAsEntertainment() {
        #expect(SpendCategory.migrated("subscriptions") == "entertainment")
        #expect(SpendCategory.migrated("dining") == "dining")
        #expect(CategorySet.builtIn["subscriptions"] == nil)
        #expect(CategorySet.builtIn.builtIns.map(\.id) == ["home", "groceries", "dining", "transport", "shopping", "entertainment", "tech", "health", "fun", "other"])
    }
}
