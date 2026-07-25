import Foundation
import XCTest
@testable import JobhuntCore

/// TASK-646: which interviews/offer deadlines surface outside the job detail, and in what order.
final class MilestoneScheduleTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private func days(_ count: Double) -> Date {
        now.addingTimeInterval(count * 86400)
    }

    private func interview(
        _ jobID: String, at date: Date, kind: InterviewKind = .screen, terminal: Bool = false
    ) -> MilestoneSchedule.Interview {
        .init(jobID: jobID, scheduledAt: date, kind: kind, jobIsTerminal: terminal)
    }

    private func offer(_ jobID: String, by date: Date, terminal: Bool = false)
        -> MilestoneSchedule.OfferDeadline {
        .init(jobID: jobID, decisionBy: date, jobIsTerminal: terminal)
    }

    // MARK: - Interviews

    func testUpcomingInterviewsAreSoonestFirst() {
        let result = MilestoneSchedule.upcomingInterviews(
            [interview("c", at: days(5)), interview("a", at: days(1)), interview("b", at: days(3))],
            now: now
        )
        XCTAssertEqual(result.map(\.jobID), ["a", "b", "c"])
    }

    /// A finished interview stops being actionable — leaving it listed trains the user to ignore the section.
    func testPastInterviewsAreDropped() {
        let result = MilestoneSchedule.upcomingInterviews(
            [interview("past", at: days(-1)), interview("future", at: days(1))], now: now
        )
        XCTAssertEqual(result.map(\.jobID), ["future"])
    }

    func testInterviewExactlyNowIsStillUpcoming() {
        let result = MilestoneSchedule.upcomingInterviews([interview("a", at: now)], now: now)
        XCTAssertEqual(result.map(\.jobID), ["a"], "an interview starting right now hasn't passed")
    }

    /// Consistent with FollowUpVisibility (TASK-577) and the referral nudge filter.
    func testTerminalJobInterviewsAreExcluded() {
        let result = MilestoneSchedule.upcomingInterviews(
            [interview("archived", at: days(1), terminal: true), interview("live", at: days(2))], now: now
        )
        XCTAssertEqual(result.map(\.jobID), ["live"])
    }

    // MARK: - Offer deadlines

    /// Unlike interviews, a passed deadline is kept — a blown offer decision is precisely what the user
    /// must not miss, so it must not silently vanish.
    func testOverdueOfferDeadlineIsKeptAndSortsFirst() {
        let result = MilestoneSchedule.offerDeadlines(
            [offer("future", by: days(4)), offer("overdue", by: days(-2))], now: now
        )
        XCTAssertEqual(result.map(\.jobID), ["overdue", "future"])
    }

    func testTerminalJobOffersAreExcluded() {
        let result = MilestoneSchedule.offerDeadlines(
            [offer("archived", by: days(1), terminal: true), offer("live", by: days(2))], now: now
        )
        XCTAssertEqual(result.map(\.jobID), ["live"])
    }

    // MARK: - Urgency

    func testUrgencyClassification() {
        XCTAssertEqual(MilestoneSchedule.urgency(of: now, now: now), .today)
        XCTAssertEqual(MilestoneSchedule.urgency(of: days(-5), now: now), .overdue)
        XCTAssertEqual(MilestoneSchedule.urgency(of: days(2), now: now), .soon)
        XCTAssertEqual(MilestoneSchedule.urgency(of: days(30), now: now), .later)
    }

    /// "Today" is a calendar day, not a rolling 24 hours — an interview later this evening is today.
    func testUrgencyUsesCalendarDaysNotRollingHours() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "America/Los_Angeles"))
        let morning = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 7, day: 25, hour: 9)))
        let evening = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 7, day: 25, hour: 22)))
        XCTAssertEqual(
            MilestoneSchedule.urgency(of: evening, now: morning, calendar: calendar), .today
        )
        // Just after midnight is tomorrow, not "13 hours away".
        let justAfterMidnight = try XCTUnwrap(calendar.date(from: DateComponents(
            year: 2026,
            month: 7,
            day: 26,
            hour: 0,
            minute: 30
        )))
        XCTAssertEqual(
            MilestoneSchedule.urgency(of: justAfterMidnight, now: morning, calendar: calendar), .soon
        )
    }

    func testUrgencyRankOrdersMostUrgentFirst() {
        let ranks = [MilestoneSchedule.Urgency.overdue, .today, .soon, .later].map(\.rank)
        XCTAssertEqual(ranks, ranks.sorted(), "rank must ascend from most to least urgent")
    }

    func testDaysRemaining() {
        XCTAssertEqual(MilestoneSchedule.daysRemaining(until: days(3), now: now), 3)
        XCTAssertEqual(MilestoneSchedule.daysRemaining(until: days(-2), now: now), -2)
        XCTAssertEqual(MilestoneSchedule.daysRemaining(until: now, now: now), 0)
    }
}
