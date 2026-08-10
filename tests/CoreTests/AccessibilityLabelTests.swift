import Foundation
import XCTest
@testable import JobhuntCore

/// Fit bands: one definition behind both the colour and the spoken label (TASK-506 #4).
final class FitBandTests: XCTestCase {
    func testBandsAtTheirBoundaries() {
        XCTAssertEqual(FitBand.band(for: 100), .strong)
        XCTAssertEqual(FitBand.band(for: 85), .strong)
        XCTAssertEqual(FitBand.band(for: 84), .good)
        XCTAssertEqual(FitBand.band(for: 70), .good)
        XCTAssertEqual(FitBand.band(for: 69), .partial)
        XCTAssertEqual(FitBand.band(for: 55), .partial)
        XCTAssertEqual(FitBand.band(for: 54), .low)
        XCTAssertEqual(FitBand.band(for: 0), .low)
    }

    /// #1: both the number and the band. The number alone means nothing without the scale; the band
    /// alone loses the difference between a 55 and a 69.
    func testAccessibilityLabelCarriesBothTheScoreAndTheBand() {
        let label = FitBand.accessibilityLabel(score: 88)
        XCTAssertTrue(label.contains("88"), label)
        XCTAssertTrue(label.contains("out of 100"), label)
        XCTAssertTrue(label.contains("Strong fit"), label)
    }

    /// An unscored job is a real state and must not read as zero — which is a *bad* score, not a
    /// missing one.
    func testUnscoredIsNotZero() {
        XCTAssertFalse(FitBand.unscoredAccessibilityLabel.contains("0"))
        XCTAssertNotEqual(
            FitBand.unscoredAccessibilityLabel, FitBand.accessibilityLabel(score: 0)
        )
    }

    /// Every band needs words, or a score in that band speaks as a bare number.
    func testEveryBandHasALabel() {
        for band in FitBand.allCases {
            XCTAssertFalse(band.label.isEmpty, "\(band)")
        }
    }
}

/// Requirement verdicts (TASK-506 #3).
final class RequirementVerdictDisplayTests: XCTestCase {
    func testParsesTheStatusStringsTheModelReturns() {
        XCTAssertEqual(RequirementVerdictDisplay(status: "met"), .met)
        XCTAssertEqual(RequirementVerdictDisplay(status: "partial"), .partial)
        XCTAssertEqual(RequirementVerdictDisplay(status: "missing"), .missing)
        XCTAssertNil(RequirementVerdictDisplay(status: "something-else"))
    }

    /// Distinct *shapes*, not just distinct colours — the state has to survive greyscale.
    func testEachVerdictHasItsOwnSymbol() {
        let symbols = Set(RequirementVerdictDisplay.allCases.map(\.systemImage))
        XCTAssertEqual(symbols.count, RequirementVerdictDisplay.allCases.count)
    }

    func testAccessibilityLabelLeadsWithTheVerdict() {
        let label = RequirementVerdictDisplay.missing.accessibilityLabel(requirement: "CUDA")
        XCTAssertTrue(label.hasPrefix("Not met"), label)
        XCTAssertTrue(label.contains("CUDA"), label)
    }
}

/// The one sentence a job row speaks (TASK-506 #2).
final class JobRowAccessibilityTests: XCTestCase {
    private func label(
        title: String? = "Staff TPM",
        company: String? = "Acme",
        location: String? = "Remote",
        salary: String? = "$180k–$220k",
        fitScore: Int? = 88,
        status: String = "Pursuing",
        isUnread: Bool = false
    ) -> String {
        JobRowAccessibility.label(
            title: title, company: company, location: location, salary: salary,
            fitScore: fitScore, status: status, isUnread: isUnread
        )
    }

    func testReadsAsOneSentenceWithEverythingOnTheRow() {
        let text = label()
        for expected in ["Staff TPM at Acme", "88", "Strong fit", "Remote", "$180k–$220k", "Pursuing"] {
            XCTAssertTrue(text.contains(expected), "missing \(expected) in: \(text)")
        }
    }

    /// The two things you scan a list for come first; bookkeeping follows.
    func testRoleAndFitLeadTheSentence() {
        let text = label()
        let role = try? XCTUnwrap(text.range(of: "Staff TPM"))
        let status = try? XCTUnwrap(text.range(of: "Pursuing"))
        XCTAssertNotNil(role)
        XCTAssertNotNil(status)
        if let role, let status { XCTAssertTrue(role.lowerBound < status.lowerBound) }
    }

    /// An unscored job says so. "No score" and "a bad score" are different situations, and silence
    /// would make them sound the same.
    func testUnscoredJobSaysSo() {
        XCTAssertTrue(label(fitScore: nil).contains("Not yet scored"))
    }

    /// Missing fields are omitted, not spoken as empty — a row shouldn't say ". . ." at the user.
    func testEmptyFieldsAreOmitted() {
        let text = label(company: nil, location: "", salary: "   ")
        XCTAssertFalse(text.contains(" at "), text)
        XCTAssertFalse(text.contains(". ."), text)
    }

    func testUntitledJobStillHasAName() {
        XCTAssertTrue(label(title: nil, company: nil).hasPrefix("Untitled job"))
    }

    /// Unread is last: it's the least important thing about the row and the most in the way if
    /// spoken first.
    func testUnreadIsMentionedLast() {
        let text = label(isUnread: true)
        XCTAssertTrue(text.hasSuffix("Unread"), text)
    }
}
