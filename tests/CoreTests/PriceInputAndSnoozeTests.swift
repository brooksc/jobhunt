import Foundation
import XCTest
@testable import JobhuntCore

/// Prices the user types, and why one gets rejected (TASK-502 #3).
final class PriceInputTests: XCTestCase {
    private func value(_ text: String) -> Double?? {
        try? PriceInput.parse(text).get()
    }

    func testParsesAPlainNumber() {
        XCTAssertEqual(value("0.25"), 0.25)
        XCTAssertEqual(value(" 3 "), 3)
    }

    /// Accepting a leading "$" is cheaper than explaining why it isn't allowed.
    func testAcceptsACurrencySymbol() {
        XCTAssertEqual(value("$1.50"), 1.5)
    }

    /// The bug this fixes: the value was dropped in silence and nothing said so.
    func testRejectsNonNumbersWithAReason() {
        XCTAssertEqual(PriceInput.parse("abc"), .failure(.notANumber))
        XCTAssertEqual(PriceInput.parse("1.2.3"), .failure(.notANumber))
        XCTAssertNotNil(PriceInput.validationMessage("abc"))
    }

    func testRejectsNegativePrices() {
        XCTAssertEqual(PriceInput.parse("-1"), .failure(.negative))
    }

    /// Blank is valid-but-absent, not an error: clearing a field is normal mid-edit, and flagging it
    /// would put a red error under every field the user is currently working in. The caller leaves
    /// the stored price alone.
    func testBlankIsValidAndCarriesNoValue() {
        XCTAssertNil(PriceInput.validationMessage(""))
        XCTAssertEqual(try? PriceInput.parse("   ").get(), Double?.none)
    }

    /// `inf` parses as a Double and would render as a nonsense estimate.
    func testRejectsInfinity() {
        XCTAssertEqual(PriceInput.parse("inf"), .failure(.notANumber))
    }
}

/// Turning a picked date into the day count the snooze path already speaks (TASK-502 #1).
final class SnoozeDefaultsTests: XCTestCase {
    private let calendar = Calendar(identifier: .gregorian)
    private let now = Date(timeIntervalSince1970: 1_760_000_000)

    func testDefaultOpensAWeekOut() {
        let start = SnoozeDefaults.defaultCustomDate(from: now, calendar: calendar)
        XCTAssertEqual(SnoozeDefaults.days(until: start, from: now, calendar: calendar), 7)
    }

    /// Calendar days, not elapsed hours: picking tomorrow morning on a late evening is 0.6 days of
    /// elapsed time and would truncate to 0 — snoozing something to right now.
    func testTomorrowMorningIsOneDayEvenFromLateEvening() throws {
        var components = calendar.dateComponents([.year, .month, .day], from: now)
        components.hour = 23
        let lateEvening = try XCTUnwrap(calendar.date(from: components))
        let tomorrowMorning = try XCTUnwrap(
            calendar.date(byAdding: .hour, value: 8, to: lateEvening)
        )
        XCTAssertEqual(
            SnoozeDefaults.days(until: tomorrowMorning, from: lateEvening, calendar: calendar), 1
        )
    }

    /// A past date floors to tomorrow rather than erroring — the least surprising reading of
    /// "snooze until yesterday", and it keeps the action out of today's list either way.
    func testPastDatesFloorToOneDay() {
        let yesterday = now.addingTimeInterval(-86400 * 3)
        XCTAssertEqual(SnoozeDefaults.days(until: yesterday, from: now, calendar: calendar), 1)
    }

    func testFutureDateCountsWholeDays() {
        let target = now.addingTimeInterval(86400 * 12)
        XCTAssertEqual(SnoozeDefaults.days(until: target, from: now, calendar: calendar), 12)
    }
}
