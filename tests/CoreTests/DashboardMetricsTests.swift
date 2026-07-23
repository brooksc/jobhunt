import Foundation
import XCTest
@testable import JobhuntCore

/// TASK-583: the 30-day Daily Activity window is driven by an explicit `now` (a day token that ticks
/// at local midnight) rather than an implicit `Date()`, so the window advances when the calendar day
/// changes. These tests pin `now` to prove the window shifts across a simulated day boundary.
final class DashboardMetricsTests: XCTestCase {
    private let cal = Calendar.current

    /// A fixed wall-clock instant, mid-morning so start-of-day math is unambiguous.
    private func fixed(_ year: Int, _ month: Int, _ day: Int, hour: Int = 10) -> Date {
        cal.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
        // swiftlint:disable:previous force_unwrapping
    }

    func testWindowIs30BucketsEndingOnToday() {
        let now = fixed(2026, 3, 15)
        let activity = DashboardMetrics.buildDailyActivity(captures: [], now: now)
        XCTAssertEqual(activity.count, 30, "window is 30 calendar-day buckets")
        // swiftlint:disable:next empty_count — `.count` is the per-day capture tally, not Collection.count
        XCTAssertTrue(activity.allSatisfy { $0.count == 0 }, "no captures → all zero")
        XCTAssertEqual(activity.last?.day, cal.startOfDay(for: now), "last bucket is today (start of day)")
        // Ascending, oldest → newest.
        let days = activity.map(\.day)
        XCTAssertEqual(days, days.sorted(), "buckets sorted oldest → newest")
    }

    func testCaptureCountedOnItsCalendarDay() {
        let now = fixed(2026, 3, 15)
        let capture = (capturedAt: fixed(2026, 3, 15, hour: 9), id: "a")
        let activity = DashboardMetrics.buildDailyActivity(captures: [capture], now: now)
        XCTAssertEqual(activity.last?.count, 1, "today's capture lands in today's bucket")
        XCTAssertEqual(activity.dropLast().reduce(0) { $0 + $1.count }, 0, "no other bucket counts it")
    }

    func testWindowAdvancesAcrossDayBoundary() throws {
        // A capture at day0. As `now` advances, the same capture moves toward the window's tail and
        // eventually falls out — proving the window advances with the calendar day.
        let day0 = fixed(2026, 3, 15)
        let capture = (capturedAt: day0, id: "a")

        // Same day: capture is the newest bucket.
        let sameDay = DashboardMetrics.buildDailyActivity(captures: [capture], now: day0)
        XCTAssertEqual(sameDay.first?.count, 0)
        XCTAssertEqual(sameDay.last?.count, 1, "capture is today")

        // 29 days later: window is [day0, day0+29]; the capture is still in-window at the oldest bucket.
        let day29 = try XCTUnwrap(cal.date(byAdding: .day, value: 29, to: day0))
        let at29 = DashboardMetrics.buildDailyActivity(captures: [capture], now: day29)
        XCTAssertEqual(at29.first?.count, 1, "on the last in-window day the capture is the oldest bucket")
        XCTAssertEqual(at29.first?.day, cal.startOfDay(for: day0))

        // 30 days later: window is [day0+1, day0+30]; the capture has aged out entirely.
        let day30 = try XCTUnwrap(cal.date(byAdding: .day, value: 30, to: day0))
        let at30 = DashboardMetrics.buildDailyActivity(captures: [capture], now: day30)
        // swiftlint:disable:next empty_count — `.count` is the per-day capture tally, not Collection.count
        XCTAssertTrue(at30.allSatisfy { $0.count == 0 }, "capture falls out of the window after 30 days")
    }

    // MARK: - TASK-623: daily recap

    private func ev(_ type: String, _ note: String?, _ date: Date) -> DashboardMetrics.RecapEvent {
        .init(eventType: type, note: note, occurredAt: date)
    }

    func testDailyRecap_countsUserActionsAndExcludesBackground() {
        let day = fixed(2026, 3, 15)
        let events: [DashboardMetrics.RecapEvent] = [
            ev("capture", nil, fixed(2026, 3, 15, hour: 9)),
            ev("captured", nil, fixed(2026, 3, 15, hour: 8)), // legacy capture name
            ev("status", "Status changed from new to pursuing", fixed(2026, 3, 15, hour: 10)),
            ev("status", "Status changed from pursuing to applied", fixed(2026, 3, 15, hour: 11)),
            ev("status", "Status changed from applied to interview", fixed(2026, 3, 15, hour: 12)),
            ev("status", "Status changed from new to passed", fixed(2026, 3, 15, hour: 13)),
            ev("duplicate_decided", "duplicate", fixed(2026, 3, 15, hour: 14)),
            ev("note", "called recruiter", fixed(2026, 3, 15, hour: 15)),
            // Background / non-user — must NOT count:
            ev("extraction", "gemini", fixed(2026, 3, 15, hour: 9)),
            ev("extraction_queued", nil, fixed(2026, 3, 15, hour: 9)),
            ev("duplicate_detected", nil, fixed(2026, 3, 15, hour: 9)),
            ev("availability", "gone", fixed(2026, 3, 15, hour: 9)),
            // Different day — must NOT count:
            ev("capture", nil, fixed(2026, 3, 14, hour: 9))
        ]
        let recap = DashboardMetrics.buildDailyRecap(events: events, followUpCompletions: [], day: day, calendar: cal)
        XCTAssertEqual(recap.captured, 2)
        XCTAssertEqual(recap.movedToInterested, 1)
        XCTAssertEqual(recap.applied, 1)
        XCTAssertEqual(recap.interviews, 1)
        XCTAssertEqual(recap.triaged, 1)
        XCTAssertEqual(recap.duplicatesResolved, 1)
        XCTAssertEqual(recap.notesAdded, 1)
        XCTAssertEqual(recap.total, 8, "8 meaningful actions; background + other-day events excluded")
        XCTAssertTrue(recap.hasActivity)
    }

    func testDailyRecap_emptyWhenNoUserActivity() {
        let day = fixed(2026, 3, 15)
        let events = [ev("extraction", "gemini", fixed(2026, 3, 15)), ev("duplicate_detected", nil, fixed(2026, 3, 15))]
        let recap = DashboardMetrics.buildDailyRecap(events: events, followUpCompletions: [], day: day, calendar: cal)
        XCTAssertFalse(recap.hasActivity)
        XCTAssertEqual(recap.total, 0)
    }

    func testDailyRecap_countsFollowUpsCompletedOnTheDay() {
        let day = fixed(2026, 3, 15)
        let recap = DashboardMetrics.buildDailyRecap(
            events: [],
            followUpCompletions: [fixed(2026, 3, 15, hour: 9), fixed(2026, 3, 15, hour: 16), fixed(2026, 3, 14)],
            day: day, calendar: cal
        )
        XCTAssertEqual(recap.followUpsCompleted, 2, "only the two completed today count")
    }

    func testRecapWindow_isContinuousOldestToNewestWithZeros() {
        let end = fixed(2026, 3, 15)
        let events = [
            ev("capture", nil, fixed(2026, 3, 15)), // today → 1
            ev("status", "Status changed from new to applied", fixed(2026, 3, 13)), // 2 days ago
            ev("capture", nil, fixed(2026, 3, 13)) // 2 days ago → total 2
        ]
        let window = DashboardMetrics.buildRecapWindow(
            events: events, followUpCompletions: [], days: 7, endingOn: end, calendar: cal
        )
        XCTAssertEqual(window.count, 7, "continuous 7-day window")
        XCTAssertEqual(window.last?.day, cal.startOfDay(for: end), "last bucket is today")
        XCTAssertEqual(window.last?.total, 1, "today has 1 action")
        XCTAssertEqual(window[4].total, 2, "two days ago (index 4) has 2 actions")
        XCTAssertEqual(window.map(\.day), window.map(\.day).sorted(), "buckets ascending oldest → newest")
        XCTAssertEqual(window.filter { $0.total == 0 }.count, 5, "the other five days are zero")
    }

    func testDayActivity_groupsJobsByCategoryExcludingBackgroundAndOtherDays() {
        let day = fixed(2026, 3, 15)
        let events = [
            DashboardMetrics.RecapEvent(
                eventType: "capture", note: nil, occurredAt: fixed(2026, 3, 15, hour: 9),
                jobID: "j1", jobNumber: 1, company: "Acme", title: "Engineer"
            ),
            DashboardMetrics.RecapEvent(
                eventType: "status", note: "Status changed from new to applied", occurredAt: fixed(2026, 3, 15, hour: 10),
                jobID: "j2", jobNumber: 2, company: "Globex", title: "PM"
            ),
            DashboardMetrics.RecapEvent( // background → excluded
                eventType: "extraction", note: "gemini", occurredAt: fixed(2026, 3, 15),
                jobID: "j3", jobNumber: 3, company: "X", title: "Y"
            ),
            DashboardMetrics.RecapEvent( // other day → excluded
                eventType: "capture", note: nil, occurredAt: fixed(2026, 3, 14),
                jobID: "j9", jobNumber: 9, company: "Old", title: "Z"
            )
        ]
        let followUps = [DashboardMetrics.FollowUpCompletion(
            completedAt: fixed(2026, 3, 15, hour: 11), jobID: "j2", jobNumber: 2, company: "Globex", title: "PM"
        )]
        let activity = DashboardMetrics.buildDayActivity(events: events, followUps: followUps, day: day, calendar: cal)

        XCTAssertFalse(activity.isEmpty)
        let cats = activity.sections.map(\.category)
        XCTAssertEqual(cats, [.found, .applied, .followUp], "sections in canonical order, background/other-day dropped")
        let found = activity.sections.first { $0.category == .found }
        XCTAssertEqual(found?.items.first?.jobNumber, 1)
        XCTAssertEqual(found?.items.first?.title, "Engineer")
        XCTAssertEqual(activity.sections.reduce(0) { $0 + $1.items.count }, 3, "3 auditable rows total")

        // The detail agrees with the counts (shared categorizer): found+applied here == recap's captured+applied.
        let recap = DashboardMetrics.buildDailyRecap(
            events: events, followUpCompletions: followUps.map(\.completedAt), day: day, calendar: cal
        )
        XCTAssertEqual(recap.captured, found?.items.count)
        XCTAssertEqual(recap.applied + recap.followUpsCompleted, 2)
    }

    func testDailyRecap_bucketsByTheCalendarTimeZone() {
        // One instant, two zones: 06:30 UTC on Mar 15 is 22:30 Mar 14 in Los Angeles.
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC")!
        var la = Calendar(identifier: .gregorian)
        la.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        let instant = utc.date(from: DateComponents(year: 2026, month: 3, day: 15, hour: 6, minute: 30))!
        let event = DashboardMetrics.RecapEvent(eventType: "capture", note: nil, occurredAt: instant)
        let mar15 = utc.date(from: DateComponents(year: 2026, month: 3, day: 15, hour: 12))!
        let mar14 = utc.date(from: DateComponents(year: 2026, month: 3, day: 14, hour: 12))!

        func captured(_ day: Date, _ cal: Calendar) -> Int {
            DashboardMetrics.buildDailyRecap(events: [event], followUpCompletions: [], day: day, calendar: cal).captured
        }
        XCTAssertEqual(captured(mar15, utc), 1, "in UTC the event is on Mar 15")
        XCTAssertEqual(captured(mar14, la), 1, "in LA the same instant is Mar 14")
        XCTAssertEqual(captured(mar15, la), 0, "so it is NOT on Mar 15 in LA")
    }

    func testStatusTarget_parsesCurrentAndLegacyNotes() {
        XCTAssertEqual(DashboardMetrics.statusTarget(fromNote: "Status changed from applied to rejected"), "rejected")
        XCTAssertEqual(DashboardMetrics.statusTarget(fromNote: "Status changed from new to pursuing"), "pursuing")
        XCTAssertEqual(DashboardMetrics.statusTarget(fromNote: "applied"), "applied", "legacy single-token note")
        XCTAssertEqual(DashboardMetrics.statusTarget(fromNote: "saved"), "pursuing", "legacy vocab mapped to current")
        XCTAssertEqual(DashboardMetrics.statusTarget(fromNote: "not_available"), "expired")
        XCTAssertNil(DashboardMetrics.statusTarget(fromNote: nil))
        XCTAssertNil(DashboardMetrics.statusTarget(fromNote: "  "))
    }
}
