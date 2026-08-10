import Foundation
import XCTest
@testable import JobhuntCore

/// Narrowing a several-hundred-entry model list (TASK-665).
final class ModelFilterTests: XCTestCase {
    private let models = [
        "anthropic/claude-haiku-4-5",
        "anthropic/claude-sonnet-5",
        "deepseek/deepseek-v4-flash",
        "deepseek/deepseek-r2",
        "mistralai/ministral-14b-2512",
        "google/gemini-3.5-flash-lite"
    ]

    private func filter(_ query: String) -> [String] {
        ModelFilter.matching(query, in: models)
    }

    /// The case from the task: reaching `deepseek/…` without scrolling.
    func testVendorPrefixNarrowsToThatVendor() {
        XCTAssertEqual(filter("deep").count, 2)
        XCTAssertTrue(filter("deep").allSatisfy { $0.hasPrefix("deepseek/") })
    }

    /// Model ids are `vendor/model`, so the part a user actually knows is often in the middle. This
    /// is why a filter beats in-menu type-select, which only matches a prefix of the whole string.
    func testMatchesASegmentInTheMiddle() {
        XCTAssertEqual(filter("haiku"), ["anthropic/claude-haiku-4-5"])
        XCTAssertEqual(filter("ministral"), ["mistralai/ministral-14b-2512"])
    }

    /// Hyphens and dots separate segments too — "flash" and "lite" both name real models.
    func testMatchesAcrossHyphensAndDots() {
        XCTAssertTrue(filter("flash").contains("deepseek/deepseek-v4-flash"))
        XCTAssertTrue(filter("lite").contains("google/gemini-3.5-flash-lite"))
    }

    /// An empty field means "no filter", not "no results" — the opposite would blank the picker the
    /// moment the user cleared what they typed.
    func testEmptyQueryReturnsEverything() {
        XCTAssertEqual(filter("").count, models.count)
        XCTAssertEqual(filter("   ").count, models.count)
    }

    func testCaseInsensitive() {
        XCTAssertEqual(filter("HAIKU"), ["anthropic/claude-haiku-4-5"])
    }

    func testNoMatchesIsEmptyNotEverything() {
        XCTAssertTrue(filter("zzzz").isEmpty)
    }

    /// Order is preserved, so the list doesn't reshuffle while typing.
    func testOrderIsPreserved() {
        XCTAssertEqual(filter("a").first, models.first { filter("a").contains($0) })
    }

    /// A short list is already scannable; an always-present filter field over five items is clutter.
    func testFilterOnlyOfferedForLongLists() {
        XCTAssertFalse(ModelFilter.shouldOfferFilter(modelCount: 5))
        XCTAssertTrue(ModelFilter.shouldOfferFilter(modelCount: 300))
    }
}
