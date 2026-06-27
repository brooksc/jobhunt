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

    // MARK: - Terminal-status jobs (TASK-577)

    func testTerminalStatusJobHidesFollowUp() {
        for status in JobStatus.allCases where status.isTerminal {
            let action = JobAction(dueDate: now)
            action.job = Job(status: status)
            XCTAssertFalse(
                FollowUpVisibility.isActionable(action, now: now),
                "\(status.rawValue) is terminal → follow-up not actionable"
            )
        }
    }

    func testNonTerminalStatusJobKeepsFollowUp() {
        for status in JobStatus.allCases where !status.isTerminal {
            let action = JobAction(dueDate: now)
            action.job = Job(status: status)
            XCTAssertTrue(
                FollowUpVisibility.isActionable(action, now: now),
                "\(status.rawValue) is active → follow-up stays actionable"
            )
        }
    }

    /// Un-archiving (terminal → active) restores the follow-up with no mutation — undo is free.
    func testLeavingTerminalStatusRestoresFollowUp() {
        let action = JobAction(dueDate: now)
        let job = Job(status: .archived)
        action.job = job
        XCTAssertFalse(FollowUpVisibility.isActionable(action, now: now))
        job.status = .pursuing
        XCTAssertTrue(FollowUpVisibility.isActionable(action, now: now))
    }

    /// `rejected` is intentionally NOT terminal — a rejection can still warrant a feedback follow-up.
    func testRejectedJobKeepsFollowUp() {
        XCTAssertFalse(JobStatus.rejected.isTerminal)
        let action = JobAction(dueDate: now)
        action.job = Job(status: .rejected)
        XCTAssertTrue(FollowUpVisibility.isActionable(action, now: now))
    }
}
