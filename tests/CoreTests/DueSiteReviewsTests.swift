import Foundation
import SwiftData
import XCTest
@testable import JobhuntCore

/// The Sites screen is a scan log: bookmark a careers page, work through it, mark it done, be told
/// when it's worth another look. The marking and the interval already existed — nothing ever told
/// you (TASK-503).
final class DueSiteReviewsTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    private func item(_ id: String, _ name: String, overdue: Int = 0) -> DueSiteReviews.Item {
        DueSiteReviews.Item(id: id, name: name, daysOverdue: overdue)
    }

    // MARK: - Due-ness

    func testASiteIsDueOnceItsNextReviewHasPassed() {
        XCTAssertTrue(DueSiteReviews.isDue(nextReviewAt: now.addingTimeInterval(-60), now: now))
        XCTAssertTrue(DueSiteReviews.isDue(nextReviewAt: now, now: now), "due exactly now counts")
        XCTAssertFalse(DueSiteReviews.isDue(nextReviewAt: now.addingTimeInterval(60), now: now))
    }

    /// A site with no schedule has never been reviewed; it belongs in the screen's own bucket, not in
    /// an interruption.
    func testANeverReviewedSiteIsNotOverdue() {
        XCTAssertFalse(DueSiteReviews.isDue(nextReviewAt: nil, now: now))
    }

    func testDaysOverdueNeverGoesNegative() {
        XCTAssertEqual(DueSiteReviews.daysOverdue(nextReviewAt: now.addingTimeInterval(86400 * 3), now: now), 0)
        XCTAssertEqual(DueSiteReviews.daysOverdue(nextReviewAt: now.addingTimeInterval(-86400 * 3), now: now), 3)
    }

    // MARK: - What to say

    func testOneSiteIsNamed() {
        let note = DueSiteReviews.notification(for: [item("a", "Netflix", overdue: 5)], alreadyNotified: [])
        XCTAssertEqual(note?.title, "Time to check Netflix")
        XCTAssertEqual(note?.body, "Due for 5 days.")
        XCTAssertEqual(note?.coveredIDs, ["a"])
    }

    func testAFewSitesAreListed() {
        let note = DueSiteReviews.notification(
            for: [item("a", "Netflix"), item("b", "Stripe")], alreadyNotified: []
        )
        XCTAssertEqual(note?.title, "2 sites due for a look")
        XCTAssertEqual(note?.body, "Netflix, Stripe")
    }

    /// Past a handful, a list of names stops being information.
    func testManySitesSummarize() {
        let many = (0 ..< 9).map { item("s\($0)", "Site \($0)") }
        let note = DueSiteReviews.notification(for: many, alreadyNotified: [])
        XCTAssertEqual(note?.title, "9 sites due for a look")
        XCTAssertEqual(note?.body, "Open Sites to see which.")
        XCTAssertEqual(note?.coveredIDs.count, 9, "all nine are covered, so none re-notifies forever")
    }

    func testAlreadyNotifiedSitesAreSkipped() {
        XCTAssertNil(
            DueSiteReviews.notification(for: [item("a", "Netflix")], alreadyNotified: ["a"]),
            "a site already mentioned this session must not interrupt again"
        )
        let note = DueSiteReviews.notification(
            for: [item("a", "Netflix"), item("b", "Stripe")], alreadyNotified: ["a"]
        )
        XCTAssertEqual(note?.coveredIDs, ["b"])
    }

    func testNothingDueSaysNothing() {
        XCTAssertNil(DueSiteReviews.notification(for: [], alreadyNotified: []))
    }

    /// Same set → same id across launches, so a repeat replaces rather than stacks.
    func testNotificationIDIsStableAndSetDependent() {
        let one = DueSiteReviews.Notification(title: "t", body: "b", coveredIDs: ["a", "b"])
        let same = DueSiteReviews.Notification(title: "t", body: "b", coveredIDs: ["b", "a"])
        let other = DueSiteReviews.Notification(title: "t", body: "b", coveredIDs: ["a", "c"])
        XCTAssertEqual(one.notificationID, same.notificationID)
        XCTAssertNotEqual(one.notificationID, other.notificationID)
        XCTAssertTrue(one.notificationID.hasPrefix("site-reviews-"))
    }

    // MARK: - Store query

    func testStoreReturnsOverdueSitesWorstFirstAndSkipsExcluded() async throws {
        let container = try ModelContainerFactory.inMemory()
        let store = BackgroundStore(modelContainer: container)

        let overdueALot = Site(origin: "https://a.test", url: "https://a.test", pageTitle: "A")
        overdueALot.companyName = "Ancient"
        overdueALot.nextReviewAt = now.addingTimeInterval(-86400 * 10)

        let overdueABit = Site(origin: "https://b.test", url: "https://b.test", pageTitle: "B")
        overdueABit.companyName = "Recent"
        overdueABit.nextReviewAt = now.addingTimeInterval(-86400)

        let notYet = Site(origin: "https://c.test", url: "https://c.test", pageTitle: "C")
        notYet.nextReviewAt = now.addingTimeInterval(86400 * 5)

        let excluded = Site(origin: "https://d.test", url: "https://d.test", pageTitle: "D")
        excluded.nextReviewAt = now.addingTimeInterval(-86400 * 30)
        excluded.state = .exclude

        for site in [overdueALot, overdueABit, notYet, excluded] {
            try await store.insert(site)
        }

        let due = try await store.dueSiteReviews(now: now)
        XCTAssertEqual(due.map(\.name), ["Ancient", "Recent"], "worst-overdue first; excluded and future omitted")
        XCTAssertEqual(due.first?.daysOverdue, 10)
    }
}
