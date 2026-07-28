import XCTest
@testable import JobhuntCore

/// The dock badge counted every unread job regardless of status, so it read 144 (59 archived + 56
/// interested + 16 expired + 13 duplicate) while only 56 jobs actually awaited review.
final class UnreadBadgeScopeTests: XCTestCase {
    func testOnlyUntriagedStatusesAwaitReview() {
        XCTAssertTrue(JobStatus.new.awaitsReview)
        XCTAssertTrue(JobStatus.pursuing.awaitsReview)
    }

    /// The statuses that inflated the badge.
    func testSetAsideStatusesDoNotAwaitReview() {
        for status in [JobStatus.archived, .expired, .duplicate, .passed, .closed] {
            XCTAssertFalse(status.awaitsReview, "\(status.rawValue) is already triaged")
        }
    }

    /// Applied and beyond have been reviewed by definition — the user acted on them.
    func testAdvancedStatusesDoNotAwaitReview() {
        for status in [JobStatus.applied, .interview, .offer, .rejected] {
            XCTAssertFalse(status.awaitsReview, "\(status.rawValue) has already been acted on")
        }
    }

    func testReportedCountIsReproduced() {
        let library: [JobStatus] = Array(repeating: .archived, count: 59)
            + Array(repeating: .pursuing, count: 56)
            + Array(repeating: .expired, count: 16)
            + Array(repeating: .duplicate, count: 13)
        XCTAssertEqual(library.count, 144, "the badge the user saw")
        XCTAssertEqual(library.count { $0.awaitsReview }, 56, "the badge they expected")
    }
}
