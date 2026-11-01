import Foundation
import Testing
@testable import PoiseKit

struct ChargeDayTests {
    var chicago: Calendar { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "America/Chicago")!; return c }
    func day(_ y: Int, _ m: Int, _ d: Int) -> Date { chicago.date(from: DateComponents(year: y, month: m, day: d))! }
    func utc(_ iso: String) -> Date { ISO8601DateFormatter().date(from: iso)! }
    var now: Date { utc("2026-10-23T20:31:00Z") }   // 3:31 pm Friday in Chicago

    @Test func eveningChargeDatedTomorrowByTheBankLandsOnTheDayItHappened() {
        // Robinhood: 7:52 pm Thursday in Chicago, dated Friday.
        let d = ChargeDay.resolve(authorizedAt: utc("2026-10-23T00:52:01Z"), authorized: day(2026, 10, 23), posted: day(2026, 10, 23),
                                  seen: utc("2026-10-23T00:59:11Z"), now: now, calendar: chicago)
        #expect(d == day(2026, 10, 22))
    }

    @Test func morningChargeStaysOnItsDay() {
        let d = ChargeDay.resolve(authorizedAt: utc("2026-10-23T12:02:43Z"), authorized: day(2026, 10, 23), posted: day(2026, 10, 23),
                                  seen: utc("2026-10-23T13:00:26Z"), now: now, calendar: chicago)
        #expect(d == day(2026, 10, 23))
    }

    @Test func withoutATimeTheChargeIsNeverLaterThanWhenItWasFirstSeen() {
        let d = ChargeDay.resolve(authorizedAt: nil, authorized: day(2026, 10, 23), posted: day(2026, 10, 23),
                                  seen: utc("2026-10-23T00:59:11Z"), now: now, calendar: chicago)
        #expect(d == day(2026, 10, 22))
    }

    @Test func theBankDateStandsWhenItIsEarlierThanFirstSeen() {
        // Synced days later: the bank's date is the better answer.
        let d = ChargeDay.resolve(authorizedAt: nil, authorized: day(2026, 10, 19), posted: day(2026, 10, 20),
                                  seen: utc("2026-10-21T08:00:13Z"), now: now, calendar: chicago)
        #expect(d == day(2026, 10, 19))
    }

    @Test func postedDateIsTheLastResort() {
        let d = ChargeDay.resolve(authorizedAt: nil, authorized: nil, posted: day(2026, 10, 21), seen: nil, now: now, calendar: chicago)
        #expect(d == day(2026, 10, 21))
    }

    @Test func neverAfterToday() {
        let d = ChargeDay.resolve(authorizedAt: nil, authorized: day(2026, 10, 24), posted: day(2026, 10, 24), seen: nil, now: now, calendar: chicago)
        #expect(d == day(2026, 10, 23))
    }
}
