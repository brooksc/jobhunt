import XCTest
@testable import JobhuntCore

/// The site-review bucket policy shared by the dashboard card/schedule and the Sites screen (TASK-582).
final class SiteReviewBucketTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    private func classify(_ state: SiteState, _ next: Date?) -> SiteReviewBucket {
        SiteReviewBucket.classify(state: state, nextReviewAt: next, now: now)
    }

    func testNewSiteWithNoReviewDateIsNotYetReviewed() {
        // A brand-new site is NOT "due" — this is the dashboard/schedule mismatch the task fixes.
        XCTAssertEqual(classify(.notReviewed, nil), .notYetReviewed)
    }

    func testOverdueScheduledSite() {
        XCTAssertEqual(classify(.reviewed, now.addingTimeInterval(-86400)), .overdue)
    }

    func testDueSoonScheduledSite() {
        XCTAssertEqual(classify(.reviewed, now.addingTimeInterval(3 * 86400)), .dueSoon)
    }

    func testScheduledLaterSite() {
        XCTAssertEqual(classify(.reviewed, now.addingTimeInterval(30 * 86400)), .scheduledLater)
    }

    func testExcludedSiteIsExcludedRegardlessOfDate() {
        XCTAssertEqual(classify(.exclude, now.addingTimeInterval(-86400)), .excluded)
        XCTAssertEqual(classify(.exclude, nil), .excluded)
    }
}
