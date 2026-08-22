import XCTest
@testable import JobhuntCore

/// What the Data Quality screen offers to fix by hand (TASK-503 #2).
///
/// The screen's only remedy was re-extraction, which on a posting whose source URL has gone re-fails
/// identically — leaving Mark Reviewed, which hides the row instead of fixing it.
final class QuickFixFieldTests: XCTestCase {
    func testAMissingFieldIsOfferedForTyping() {
        XCTAssertEqual(QuickFixField.fields(for: [.missingCompany]), [.company])
        XCTAssertEqual(QuickFixField.fields(for: [.missingTitle]), [.title])
        XCTAssertEqual(QuickFixField.fields(for: [.missingLocation]), [.location])
    }

    /// Stable order regardless of how the checker happened to list the issues, so the form doesn't
    /// rearrange itself between two rows with the same problems.
    func testFieldsComeBackInAStableOrder() {
        let scrambled = QuickFixField.fields(for: [.missingLocation, .missingCompany, .missingTitle])
        XCTAssertEqual(scrambled, [.company, .title, .location])
    }

    /// Work mode is a picker and salary is a structured range. A text box that accepted "120k-ish"
    /// would leave the data worse than the gap it filled.
    func testStructuredFieldsAreNotOfferedAsFreeText() {
        XCTAssertTrue(QuickFixField.fields(for: [.missingWorkMode, .missingSalary]).isEmpty)
    }

    /// A job whose only problem is a short capture or a stale extraction has nothing to type, and an
    /// empty form is worse than no button.
    func testNothingIsOfferedWhenNoFieldApplies() {
        XCTAssertTrue(QuickFixField.fields(for: [.staleExtraction, .extractionFailed]).isEmpty)
        XCTAssertTrue(QuickFixField.fields(for: []).isEmpty)
    }

    /// Every field answers exactly one issue, so the button can't appear for a problem it can't fix.
    func testEveryFieldMapsToTheIssueItAnswers() {
        for field in QuickFixField.allCases {
            XCTAssertEqual(QuickFixField.fields(for: [field.kind]), [field], field.label)
        }
    }
}
