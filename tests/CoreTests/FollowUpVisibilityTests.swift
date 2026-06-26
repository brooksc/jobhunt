import XCTest
@testable import JobhuntCore

/// The single "actionable follow-up" predicate shared by the Needs Action screen/badge, Dashboard,
/// job detail, and export (TASK-576).
final class FollowUpVisibilityTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    // MARK: - Scalar form (all four states)

    func testActiveFollowUpIsActionable() {
        XCTAssertTrue(FollowUpVisibility.isActionable(completedAt: nil, snoozedUntil: nil, hasJob: true, now: now))
    }

    func testCompletedIsNotActionable() {
        XCTAssertFalse(FollowUpVisibility.isActionable(completedAt: now, snoozedUntil: nil, hasJob: true, now: now))
    }

    func testFutureSnoozedIsNotActionable() {
        let future = now.addingTimeInterval(3600)
        XCTAssertFalse(FollowUpVisibility.isActionable(completedAt: nil, snoozedUntil: future, hasJob: true, now: now))
    }

    func testPastSnoozeIsActionableAgain() {
        let past = now.addingTimeInterval(-3600)
        XCTAssertTrue(FollowUpVisibility.isActionable(completedAt: nil, snoozedUntil: past, hasJob: true, now: now))
    }

    func testOrphanedActionIsNotActionable() {
        XCTAssertFalse(FollowUpVisibility.isActionable(completedAt: nil, snoozedUntil: nil, hasJob: false, now: now))
    }

    // MARK: - JobAction convenience (maps `job` relationship → hasJob)

    func testJobActionConvenienceExcludesOrphanAndIncludesLinked() {
        let orphan = JobAction(dueDate: now)
        XCTAssertFalse(FollowUpVisibility.isActionable(orphan, now: now), "no linked job → not actionable")

        let linked = JobAction(dueDate: now)
        linked.job = Job(status: .new)
        XCTAssertTrue(FollowUpVisibility.isActionable(linked, now: now))

        linked.completedAt = now
        XCTAssertFalse(FollowUpVisibility.isActionable(linked, now: now), "completed → not actionable")
    }
}
