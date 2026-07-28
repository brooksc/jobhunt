import Foundation
import XCTest
@testable import JobhuntCore

/// The requirement rows encode two INDEPENDENT things — how well the résumé matches (icon) and how
/// the job weighted the requirement ("Preferred" tag). That's why "!" appears on both required and
/// preferred rows, which read as arbitrary with nothing explaining it. These pin the tooltip copy.
final class RequirementAssessmentExplanationTests: XCTestCase {
    private func assessment(status: String, kind: String) -> RequirementAssessment {
        RequirementAssessment(requirement: "K–12 curriculum expertise", kind: kind, status: status, evidence: "")
    }

    // MARK: - Match axis (the icon)

    func testEachMatchStatusIsExplained() {
        XCTAssertTrue(assessment(status: "met", kind: "required").matchExplanation.hasPrefix("Met"))
        XCTAssertTrue(assessment(status: "partial", kind: "required").matchExplanation.hasPrefix("Partially met"))
        XCTAssertTrue(assessment(status: "missing", kind: "required").matchExplanation.hasPrefix("Not met"))
    }

    /// Anything unrecognised renders as the icon does — `assessmentIcon` falls through to ✗.
    func testUnknownStatusReadsAsNotMet() {
        XCTAssertTrue(assessment(status: "", kind: "required").matchExplanation.hasPrefix("Not met"))
    }

    // MARK: - Weight axis (the "Preferred" tag)

    func testRequiredAndPreferredAreDistinguished() {
        XCTAssertTrue(assessment(status: "partial", kind: "required").weightExplanation.contains("required"))
        XCTAssertTrue(assessment(status: "partial", kind: "preferred").weightExplanation.contains("preferred"))
    }

    /// Legacy fit scores predate `kind`. An old score must not claim a requirement was "required"
    /// when that was never recorded.
    func testLegacyUnknownKindClaimsNothing() {
        XCTAssertEqual(assessment(status: "partial", kind: "unknown").weightExplanation, "")
    }

    // MARK: - Combined tooltip

    /// The exact confusion reported: the same "!" on a required and a preferred row must now read
    /// differently.
    func testSameIconOnRequiredAndPreferredExplainsTheDifference() {
        let required = assessment(status: "partial", kind: "required").explanation
        let preferred = assessment(status: "partial", kind: "preferred").explanation
        XCTAssertNotEqual(required, preferred)
        XCTAssertTrue(required.contains("Partially met") && required.contains("required"))
        XCTAssertTrue(preferred.contains("Partially met") && preferred.contains("nice-to-have"))
    }

    func testLegacyRowStillGetsAUsefulTooltip() {
        let text = assessment(status: "met", kind: "unknown").explanation
        XCTAssertTrue(text.hasPrefix("Met"))
        XCTAssertFalse(text.hasSuffix(" "), "no dangling space when the weight clause is omitted")
    }

    func testEveryCombinationProducesNonEmptyCopy() {
        for status in ["met", "partial", "missing", "weird"] {
            for kind in ["required", "preferred", "unknown"] {
                let text = assessment(status: status, kind: kind).explanation
                XCTAssertFalse(text.isEmpty, "\(status)/\(kind)")
            }
        }
    }
}
