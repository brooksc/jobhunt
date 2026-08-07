import Foundation
import XCTest
@testable import JobhuntCore

/// Variants exist so alternatives can be compared without reimplementing the arithmetic — every
/// earlier experiment re-derived the maths in a scratch script, which is how a reimplementation once
/// disagreed with `FitScorer` by a point on the first job it touched.
final class ScoringVariantTests: XCTestCase {
    /// Requirement text has to read like something a posting would actually list: the fragment filter
    /// drops bare noun phrases, so a fixture saying "required requirement 0" is silently discarded and
    /// every assertion here collapses to nil.
    private func assessments(required: [String], preferred: [String] = []) -> [[String: Any]] {
        required.enumerated().map {
            [
                "requirement": "Experience with required requirement \($0.offset)",
                "kind": "required", "status": $0.element
            ]
        } + preferred.enumerated().map {
            [
                "requirement": "Experience with preferred requirement \($0.offset)",
                "kind": "preferred", "status": $0.element
            ]
        }
    }

    private let dims = [
        "required_qualifications": 80.0, "preferred_qualifications": 60.0,
        "skills": 70.0, "domain_fit": 40.0, "experience_level": 90.0
    ]

    // MARK: - Verdict share

    func testAllMetScoresFull() {
        XCTAssertEqual(
            FitScorer.verdictShare(assessments: assessments(required: ["met", "met"]), partialCredit: 0.5),
            100
        )
    }

    func testAllMissingScoresZero() {
        XCTAssertEqual(
            FitScorer.verdictShare(assessments: assessments(required: ["missing"]), partialCredit: 0.5),
            0
        )
    }

    /// A hard requirement must outweigh a nice-to-have, or a posting with a long wish list drowns out
    /// the qualifications that actually gate the role.
    func testRequiredOutweighsPreferred() {
        let missRequired = FitScorer.verdictShare(
            assessments: assessments(required: ["missing"], preferred: ["met"]), partialCredit: 0.5
        )
        let missPreferred = FitScorer.verdictShare(
            assessments: assessments(required: ["met"], preferred: ["missing"]), partialCredit: 0.5
        )
        XCTAssertNotNil(missRequired)
        XCTAssertNotNil(missPreferred)
        XCTAssertLessThan(missRequired!, missPreferred!)
    }

    /// The denominator must drop anything the numerator drops, or removing a requirement would
    /// perversely lower the score.
    func testNonDiscriminatingRequirementsLeaveTheDenominator() {
        let withNoise = [
            ["requirement": "8 years of program management", "kind": "required", "status": "met"],
            ["requirement": "capacity to learn Jira", "kind": "required", "status": "missing"]
        ] as [[String: Any]]
        XCTAssertEqual(FitScorer.verdictShare(assessments: withNoise, partialCredit: 0.5), 100)
    }

    func testNoUsableRequirementsReturnsNil() {
        XCTAssertNil(FitScorer.verdictShare(assessments: [], partialCredit: 0.5))
    }

    /// User corrections have to apply here exactly as they do to gaps, or the score and the rows
    /// disagree — the failure this app has already shipped once.
    func testFeedbackAppliesToTheShare() {
        let a = assessments(required: ["missing"])
        let corrected = FitScorer.verdictShare(
            assessments: a, partialCredit: 0.5,
            feedback: [ScoringFeedback(phrase: "required requirement 0", kind: .alwaysCredit)],
            jobNumber: 1
        )
        XCTAssertEqual(corrected, 100)
    }

    // MARK: - Missing-required count (the user's actual triage question)

    func testMissingRequiredCountIgnoresPreferredAndPartials() {
        let a = assessments(required: ["missing", "partial", "met", "missing"], preferred: ["missing"])
        XCTAssertEqual(FitScorer.missingRequiredCount(assessments: a), 2)
    }

    // MARK: - Variants

    /// The whole point: a variant that scores well in an experiment is the one that ships.
    func testEachVariantIsDeterministicForTheSameInput() {
        let a = assessments(required: ["met", "partial", "missing"], preferred: ["met"])
        for variant in [ScoringVariant.current, .verdictShare(), .hybrid()] {
            let first = FitScorer.score(variant, dimensions: dims, assessments: a)
            for _ in 0 ..< 20 {
                XCTAssertEqual(
                    FitScorer.score(variant, dimensions: dims, assessments: a), first,
                    "\(variant.name) is not deterministic"
                )
            }
        }
    }

    /// `.verdictShare` must not consult the dimensions at all — that independence is the reason it
    /// exists as the stability baseline.
    func testVerdictShareIgnoresDimensionsEntirely() {
        let a = assessments(required: ["met", "missing"])
        XCTAssertEqual(
            FitScorer.score(.verdictShare(), dimensions: dims, assessments: a),
            FitScorer.score(.verdictShare(), dimensions: [:], assessments: a)
        )
    }

    /// The hybrid keeps exactly the two judgements a requirement list cannot express, and must
    /// actually respond to them.
    func testHybridRespondsToDomainFit() {
        let a = assessments(required: ["met", "met"])
        var poorDomain = dims
        poorDomain["domain_fit"] = 5
        XCTAssertGreaterThan(
            FitScorer.score(.hybrid(), dimensions: dims, assessments: a),
            FitScorer.score(.hybrid(), dimensions: poorDomain, assessments: a)
        )
    }

    /// …and must ignore the three it drops, or the variance those carry comes straight back.
    func testHybridIgnoresTheDroppedDimensions() {
        let a = assessments(required: ["met", "partial"])
        var churn = dims
        churn["skills"] = 10
        churn["required_qualifications"] = 10
        churn["preferred_qualifications"] = 10
        XCTAssertEqual(
            FitScorer.score(.hybrid(), dimensions: dims, assessments: a),
            FitScorer.score(.hybrid(), dimensions: churn, assessments: a)
        )
    }

    func testHybridFallsBackToContextWhenNoRequirementsAreUsable() {
        let score = FitScorer.score(.hybrid(), dimensions: dims, assessments: [])
        XCTAssertEqual(Double(score), FitScorer.contextScore(dimensions: dims), accuracy: 1)
    }
}
