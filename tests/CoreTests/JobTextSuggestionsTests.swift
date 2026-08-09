import Foundation
import XCTest
@testable import JobhuntCore

/// Completing company and job titles from the user's own data (TASK-591).
final class JobTextSuggestionsTests: XCTestCase {
    private let companies = ["Google", "Goodwill Industries", "Bright Systems", "google"]
    private let titles = ["Staff Engineer", "Engineering Manager", "Principal TPM"]

    private func suggest(_ prefix: String, limit: Int = 5) -> [JobTextSuggestions.Suggestion] {
        JobTextSuggestions.suggest(
            prefix: prefix, companies: companies, titles: titles, limit: limit
        )
    }

    /// #1: the headline case.
    func testCompanyPrefixMatches() {
        let texts = suggest("goog").map(\.text)
        XCTAssertTrue(texts.contains("Google"), "\(texts)")
        XCTAssertFalse(texts.contains("Bright Systems"), "\(texts)")
    }

    /// #3: titles complete the same way, and are tagged so the row can say which is which.
    func testTitlePrefixMatchesAndIsTagged() {
        let engineering = suggest("engineer")
        XCTAssertTrue(engineering.contains { $0.text == "Engineering Manager" && $0.kind == .title })
        XCTAssertTrue(engineering.allSatisfy { $0.kind == .title })
    }

    /// Prefix-of-any-word, not just prefix-of-string: whole-string matching would require knowing how
    /// the name starts, which is the thing the user is trying not to have to remember.
    func testMatchesAWordInsideTheValue() {
        XCTAssertTrue(suggest("systems").map(\.text).contains("Bright Systems"))
    }

    /// A one-character prefix matches most of the corpus and would bury the structured token
    /// suggestions that share this dropdown.
    func testTooShortAPrefixSuggestsNothing() {
        XCTAssertTrue(suggest("g").isEmpty)
        XCTAssertTrue(suggest("").isEmpty)
    }

    /// Duplicates differing only in case are one suggestion — but the first spelling seen wins, so
    /// inserting it doesn't look like a typo of the user's own data.
    func testCaseInsensitiveDedupKeepsTheOriginalSpelling() {
        let matches = suggest("google").filter { $0.kind == .company }
        XCTAssertEqual(matches.count, 1)
        XCTAssertEqual(matches.first?.text, "Google")
    }

    /// The limit is per kind: a company with many near-matches must not crowd titles out entirely.
    func testLimitIsPerKindNotTotal() {
        let result = JobTextSuggestions.suggest(
            prefix: "en",
            companies: ["Enable", "Encore", "Endeavour"],
            titles: ["Engineer"],
            limit: 2
        )
        XCTAssertEqual(result.count(where: { $0.kind == .company }), 2)
        XCTAssertEqual(result.count(where: { $0.kind == .title }), 1)
    }

    func testBlankValuesAreIgnored() {
        let result = JobTextSuggestions.suggest(
            prefix: "ac", companies: ["", "   ", "Acme"], titles: []
        )
        XCTAssertEqual(result.map(\.text), ["Acme"])
    }
}
