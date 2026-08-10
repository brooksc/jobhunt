import Foundation
import XCTest
@testable import JobhuntCore

/// The written recap and the reminder schedule (TASK-623 #3, #8, #9, #11).
final class DailyRecapNarrativeTests: XCTestCase {
    private func recap(_ configure: (inout DailyRecap) -> Void) -> DailyRecap {
        var recap = DailyRecap()
        configure(&recap)
        return recap
    }

    /// #3: prose, not a counter list. "You sent 3 applications" reads like an accomplishment;
    /// "applied: 3" reads like a dashboard.
    func testSentenceReadsAsProse() {
        let text = recap { $0.applied = 3 }.recapSentence
        XCTAssertEqual(text, "Today you sent 3 applications.")
    }

    func testSingularAndPluralAgree() {
        XCTAssertTrue(recap { $0.applied = 1 }.recapSentence.contains("1 application."))
        XCTAssertTrue(recap { $0.applied = 2 }.recapSentence.contains("2 applications"))
    }

    /// Ordered by what a job seeker is likeliest to feel good about, not by count — an offer beats
    /// twelve saved jobs.
    func testBiggerMilestonesLeadTheSentence() {
        let text = recap {
            $0.captured = 12
            $0.offers = 1
        }.recapSentence
        XCTAssertTrue(text.hasPrefix("Today you received 1 offer"), text)
    }

    /// A sentence with ten clauses stops being a sentence.
    func testLongDaysAreSummarised() {
        let text = recap {
            $0.applied = 1; $0.captured = 2; $0.notesAdded = 3
            $0.triaged = 4; $0.followUpsCompleted = 5
        }.recapSentence
        XCTAssertTrue(text.contains("more thing"), text)
        XCTAssertLessThanOrEqual(text.components(separatedBy: ", ").count, 4, text)
    }

    func testTwoClausesUseAndNotAComma() {
        let text = recap { $0.applied = 1; $0.notesAdded = 1 }.recapSentence
        XCTAssertTrue(text.contains("and"), text)
        XCTAssertFalse(text.contains(","), text)
    }

    /// #9: a day with nothing on it gets a neutral statement. No streak language, no failure state,
    /// nothing implying the user owes the app anything.
    func testEmptyDayIsNeutral() {
        let text = DailyRecap().recapSentence
        XCTAssertEqual(text, "No tracked activity today.")
        for loaded in ["streak", "missed", "failed", "behind", "should"] {
            XCTAssertFalse(text.lowercased().contains(loaded), "recap must not say '\(loaded)'")
        }
    }

    /// No pressure language on a busy day either.
    func testBusyDayCarriesNoPressureLanguage() {
        let text = recap { $0.applied = 5 }.recapSentence.lowercased()
        for loaded in ["streak", "keep it up", "don't break", "goal", "quota"] {
            XCTAssertFalse(text.contains(loaded), "recap must not say '\(loaded)'")
        }
    }
}

/// #8/#11: the reminder's day boundaries.
final class RecapReminderScheduleTests: XCTestCase {
    private var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles") ?? .gmt
        return calendar
    }()

    private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(
            year: year, month: month, day: day, hour: hour, minute: minute
        )) ?? Date()
    }

    func testFiresLaterTheSameDayWhenTheHourHasntArrived() {
        let now = date(2026, 8, 9, 9)
        let next = RecapReminderSchedule.nextFireDate(after: now, hour: 18, calendar: calendar)
        XCTAssertEqual(next, date(2026, 8, 9, 18))
    }

    /// Past the hour, it's tomorrow — not immediately, which would fire on every tick.
    func testRollsToTomorrowOnceThePasses() {
        let now = date(2026, 8, 9, 19)
        let next = RecapReminderSchedule.nextFireDate(after: now, hour: 18, calendar: calendar)
        XCTAssertEqual(next, date(2026, 8, 10, 18))
    }

    /// Exactly on the hour counts as passed. At-or-after would re-fire in a loop.
    func testExactlyOnTheHourRollsForward() {
        let now = date(2026, 8, 9, 18)
        let next = RecapReminderSchedule.nextFireDate(after: now, hour: 18, calendar: calendar)
        XCTAssertEqual(next, date(2026, 8, 10, 18))
    }

    /// #8: across a DST spring-forward, the reminder stays at the same *wall-clock* hour rather than
    /// drifting an hour twice a year. 2026-03-08 is the US transition.
    func testHoldsTheWallClockHourAcrossDST() throws {
        let beforeTransition = date(2026, 3, 7, 20)
        let next = try XCTUnwrap(
            RecapReminderSchedule.nextFireDate(after: beforeTransition, hour: 18, calendar: calendar)
        )
        XCTAssertEqual(calendar.component(.hour, from: next), 18)
        XCTAssertEqual(calendar.component(.day, from: next), 8)
    }

    /// The same instant belongs to different days in different zones; the schedule follows the
    /// calendar it's handed rather than assuming UTC.
    func testUsesTheSuppliedTimeZone() throws {
        var tokyo = Calendar(identifier: .gregorian)
        tokyo.timeZone = try XCTUnwrap(TimeZone(identifier: "Asia/Tokyo"))
        let instant = date(2026, 8, 9, 9) // 09:00 Los Angeles = 01:00 next day in Tokyo
        let losAngeles = RecapReminderSchedule.nextFireDate(after: instant, hour: 18, calendar: calendar)
        let inTokyo = RecapReminderSchedule.nextFireDate(after: instant, hour: 18, calendar: tokyo)
        XCTAssertNotEqual(losAngeles, inTokyo)
    }

    /// A stored hour outside 0–23 must not produce a date in the past forever.
    func testOutOfRangeHourIsClamped() throws {
        let now = date(2026, 8, 9, 9)
        let high = try XCTUnwrap(RecapReminderSchedule.nextFireDate(after: now, hour: 99, calendar: calendar))
        let low = try XCTUnwrap(RecapReminderSchedule.nextFireDate(after: now, hour: -5, calendar: calendar))
        XCTAssertGreaterThan(high, now)
        XCTAssertGreaterThan(low, now)
    }
}
