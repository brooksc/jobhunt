import XCTest
@testable import JobhuntCore

/// Extraction judges `meetsCriteria` against preferred locations *combined with expanded metros*,
/// so a recompute that used the raw field would disagree with the verdict a job got when captured.
/// Both paths now share `combinedPreferredLocations`.
final class CombinedPreferredLocationsTests: XCTestCase {
    func testManualLocationsPassThrough() {
        XCTAssertEqual(combinedPreferredLocations(locations: "United States", metros: ""), "United States")
    }

    func testEmptyInputsProduceEmptyString() {
        XCTAssertEqual(combinedPreferredLocations(locations: "", metros: ""), "")
        XCTAssertEqual(combinedPreferredLocations(locations: nil, metros: nil), "")
    }

    func testWhitespaceAndEmptyEntriesAreDropped() {
        XCTAssertEqual(combinedPreferredLocations(locations: " Texas , , Ohio ", metros: ""), "Texas, Ohio")
    }

    func testMetrosAreExpandedAndAppended() {
        let combined = combinedPreferredLocations(locations: "Texas", metros: "ca:bay-area")
        XCTAssertTrue(combined.hasPrefix("Texas, "), combined)
        XCTAssertTrue(combined.contains("San Francisco"), combined)
    }

    /// A city named manually and again via its metro must not appear twice.
    func testDuplicatesAreRemovedCaseInsensitively() {
        let combined = combinedPreferredLocations(locations: "san francisco", metros: "ca:bay-area")
        // Compare whole entries — a substring test would also count "South San Francisco".
        let entries = combined.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
        XCTAssertEqual(entries.count(where: { $0 == "san francisco" }), 1, combined)
        XCTAssertTrue(entries.contains("south san francisco"), "the distinct city must survive")
    }

    /// The property that matters: whatever extraction judged against, the recompute judges against.
    func testRecomputeAndExtractionAgreeOnTheSameTerms() {
        let locations = "Texas"
        let metros = "ca:bay-area"
        let terms = parsePreferredLocations(combinedPreferredLocations(locations: locations, metros: metros))
        XCTAssertTrue(terms.contains { termMatches("San Francisco, CA", term: $0) })
        XCTAssertTrue(terms.contains { termMatches("Austin, TX", term: $0) })
    }
}
