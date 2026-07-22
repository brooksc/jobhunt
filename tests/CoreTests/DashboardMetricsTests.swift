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
}
