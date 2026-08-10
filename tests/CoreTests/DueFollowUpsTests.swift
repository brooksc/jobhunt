import Foundation
import XCTest
@testable import JobhuntCore

/// Which follow-ups are due, and what gets said about them (TASK-589).
final class DueFollowUpsTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_770_000_000)

    private func item(_ id: String, jobNumber: Int? = 1) -> DueFollowUps.Item {
        DueFollowUps.Item(
            id: id, jobNumber: jobNumber, title: "Staff TPM", company: "Acme", note: "Ping recruiter"
        )
    }

    // MARK: - Due-ness

    func testDueWhenPastAndIncomplete() {
        XCTAssertTrue(DueFollowUps.isDue(
            dueDate: now.addingTimeInterval(-60), completedAt: nil, snoozedUntil: nil, now: now
        ))
    }

    func testNotDueBeforeTheDueDate() {
        XCTAssertFalse(DueFollowUps.isDue(
            dueDate: now.addingTimeInterval(3600), completedAt: nil, snoozedUntil: nil, now: now
        ))
    }

    func testCompletedIsNeverDue() {
        XCTAssertFalse(DueFollowUps.isDue(
            dueDate: now.addingTimeInterval(-60), completedAt: now, snoozedUntil: nil, now: now
        ))
    }

    /// #2: a live snooze suppresses it.
    func testSnoozedIntoTheFutureIsNotDue() {
        XCTAssertFalse(DueFollowUps.isDue(
            dueDate: now.addingTimeInterval(-86400), completedAt: nil,
            snoozedUntil: now.addingTimeInterval(3600), now: now
        ))
    }

    /// The other half of #2, and the one that would silence a follow-up forever if it were wrong: a
    /// snooze whose time has passed is an *expired* snooze, so the follow-up is due again.
    func testExpiredSnoozeIsDueAgain() {
        XCTAssertTrue(DueFollowUps.isDue(
            dueDate: now.addingTimeInterval(-86400), completedAt: nil,
            snoozedUntil: now.addingTimeInterval(-60), now: now
        ))
    }

    // MARK: - What to say

    func testNothingDueSaysNothing() {
        XCTAssertNil(DueFollowUps.notification(for: [], alreadyNotified: []))
    }

    /// #3: the second cycle over the same follow-up is silent.
    func testAlreadyNotifiedIsNotRepeated() {
        XCTAssertNil(DueFollowUps.notification(for: [item("a")], alreadyNotified: ["a"]))
    }

    func testANewOneAmongNotifiedOnesStillFires() throws {
        let notification = try XCTUnwrap(
            DueFollowUps.notification(for: [item("a"), item("b")], alreadyNotified: ["a"])
        )
        XCTAssertEqual(notification.coveredIDs, ["b"])
    }

    /// #4: one due follow-up deep-links to its job.
    func testSingleFollowUpCarriesItsJobNumber() throws {
        let notification = try XCTUnwrap(
            DueFollowUps.notification(for: [item("a", jobNumber: 42)], alreadyNotified: [])
        )
        XCTAssertEqual(notification.jobNumber, 42)
        XCTAssertTrue(notification.body.contains("Staff TPM at Acme"), notification.body)
    }

    /// With several due, opening an arbitrary one would be worse than opening none — the caller
    /// routes a nil job number to the Needs Action list.
    func testSeveralFollowUpsDoNotDeepLinkToOne() throws {
        let items = (1 ... 3).map { item("id-\($0)", jobNumber: $0) }
        let notification = try XCTUnwrap(DueFollowUps.notification(for: items, alreadyNotified: []))
        XCTAssertNil(notification.jobNumber)
        XCTAssertEqual(notification.coveredIDs.count, 3)
    }

    /// Past the cap it summarizes — but still covers every id. Marking only the named ones would
    /// re-notify the remainder on every subsequent cycle, forever.
    func testLargeBatchSummarizesButCoversEveryID() throws {
        let items = (1 ... 9).map { item("id-\($0)", jobNumber: $0) }
        let notification = try XCTUnwrap(DueFollowUps.notification(for: items, alreadyNotified: []))
        XCTAssertTrue(notification.title.contains("9 follow-ups"), notification.title)
        XCTAssertEqual(notification.coveredIDs.count, 9)
        XCTAssertFalse(notification.body.contains("Staff TPM"), "a summary shouldn't list them")
    }

    /// A follow-up on a job with no title or company still says something usable.
    func testFallsBackToTheNoteWhenTheJobIsUnnamed() throws {
        let bare = DueFollowUps.Item(
            id: "x", jobNumber: 7, title: "", company: nil, note: "Email the hiring manager"
        )
        let notification = try XCTUnwrap(DueFollowUps.notification(for: [bare], alreadyNotified: []))
        XCTAssertEqual(notification.body, "Email the hiring manager")
    }
}
