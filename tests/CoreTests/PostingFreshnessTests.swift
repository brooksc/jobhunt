import Foundation
import XCTest
@testable import JobhuntCore

/// How old a posting is, and how much of that we actually know (TASK-633).
final class PostingFreshnessTests: XCTestCase {
    private let calendar = Calendar(identifier: .gregorian)
    private let now = Date(timeIntervalSince1970: 1_770_000_000)

    private func daysAgo(_ days: Int) -> Date {
        calendar.date(byAdding: .day, value: -days, to: now) ?? now
    }

    private func make(
        firstPublished: Date? = nil,
        atsUpdated: Date? = nil,
        capturedAt: Date? = nil
    ) -> PostingFreshness? {
        PostingFreshness.make(
            firstPublished: firstPublished,
            atsUpdated: atsUpdated,
            capturedAt: capturedAt,
            now: now,
            calendar: calendar
        )
    }

    /// #1: with an ATS date, the label is authoritative and says "Posted".
    func testATSDateIsAuthoritative() throws {
        let freshness = try XCTUnwrap(make(firstPublished: daysAgo(2)))
        XCTAssertEqual(freshness.confidence, .authoritative)
        XCTAssertEqual(freshness.level, .fresh)
        XCTAssertTrue(freshness.label.hasPrefix("Posted"), freshness.label)
    }

    /// #3, and the reason the wording differs: presenting a capture date as a posting date is a lie
    /// in the one direction that matters — it always makes a posting look newer than it is.
    func testCaptureDateFallbackSaysCaptured() throws {
        let freshness = try XCTUnwrap(make(capturedAt: daysAgo(3)))
        XCTAssertEqual(freshness.confidence, .captureDate)
        XCTAssertTrue(freshness.label.hasPrefix("Captured"), freshness.label)
    }

    /// The ATS date wins even when we also have a capture date — that's the whole point of fetching
    /// it, since a posting found weeks after it went up looks new by capture date.
    func testATSDateBeatsTheCaptureDate() throws {
        let freshness = try XCTUnwrap(make(firstPublished: daysAgo(60), capturedAt: daysAgo(1)))
        XCTAssertEqual(freshness.level, .stale)
        XCTAssertEqual(freshness.confidence, .authoritative)
    }

    /// `first_published` is preferred over `updated_at`: the latter moves whenever the employer
    /// fixes a typo, which would make an ancient requisition read as new.
    func testFirstPublishedIsPreferredOverUpdatedAt() throws {
        let freshness = try XCTUnwrap(
            make(firstPublished: daysAgo(90), atsUpdated: daysAgo(1))
        )
        XCTAssertEqual(freshness.level, .stale)
    }

    /// #2: the bands.
    func testLevelBands() throws {
        XCTAssertEqual(try XCTUnwrap(make(firstPublished: daysAgo(1))).level, .fresh)
        XCTAssertEqual(try XCTUnwrap(make(firstPublished: daysAgo(10))).level, .recent)
        XCTAssertEqual(try XCTUnwrap(make(firstPublished: daysAgo(30))).level, .aging)
        XCTAssertEqual(try XCTUnwrap(make(firstPublished: daysAgo(60))).level, .stale)
    }

    /// A posting maintained long after it opened is the shape of a repost or a long-running
    /// requisition — worth flagging, since it bears on how active the search is.
    func testLongGapBetweenPublishAndUpdateReadsAsARepost() throws {
        let freshness = try XCTUnwrap(
            make(firstPublished: daysAgo(80), atsUpdated: daysAgo(2))
        )
        XCTAssertTrue(freshness.isRepost)
        XCTAssertTrue(freshness.label.contains("updated since"), freshness.label)
    }

    /// Fixing a typo the next day is not a repost.
    func testASmallGapIsNotARepost() throws {
        let freshness = try XCTUnwrap(
            make(firstPublished: daysAgo(10), atsUpdated: daysAgo(9))
        )
        XCTAssertFalse(freshness.isRepost)
    }

    /// Nothing to go on means no label, rather than a confident-looking "posted today".
    func testNoDatesMeansNoLabel() {
        XCTAssertNil(make())
    }

    /// A future date (clock skew, or an ATS scheduling a posting) must not render as a negative age.
    func testFutureDatesClampToToday() throws {
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: now) ?? now
        let freshness = try XCTUnwrap(make(firstPublished: tomorrow))
        XCTAssertEqual(freshness.level, .fresh)
        XCTAssertTrue(freshness.label.contains("today"), freshness.label)
    }
}
