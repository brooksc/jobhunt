import Foundation
import XCTest
@testable import JobhuntCore

/// Corrections the user makes in place, applied deterministically.
///
/// Deterministic rather than prompt-injected on measured grounds: adding one broad rule to the
/// scoring prompt regressed job #231 from a correct 60 back to 96 on gemini-3.1-flash-lite, because
/// the new instruction diluted the rules that were working. Accumulating user notes would be worse,
/// and would degrade silently.
final class ScoringFeedbackTests: XCTestCase {
    private func feedback(
        _ phrase: String, _ kind: ScoringFeedback.Kind, job: Int? = nil
    ) -> ScoringFeedback {
        ScoringFeedback(phrase: phrase, kind: kind, jobNumber: job)
    }

    // MARK: - The three reasons do different things

    /// "I don't have this" is a REAL gap: it must cost points and stay visible. Hiding it would
    /// misrepresent how well the user fits the role.
    func testNeverCreditForcesMissing() {
        let rules = [feedback("CUDA", .neverCredit)]
        XCTAssertEqual(
            rules.verdict(forRequirement: "Expertise in GPU architectures and CUDA ecosystem", jobNumber: 1),
            .forceMissing
        )
    }

    /// "Not a real requirement" is the opposite: no penalty and no display, because a zero-cost gap
    /// still reads as something to fix.
    func testNotARequirementIsIgnored() {
        let rules = [feedback("capacity to learn", .notARequirement)]
        XCTAssertEqual(
            rules.verdict(forRequirement: "Experience with, or capacity to learn, JIRA", jobNumber: 1),
            .ignore
        )
    }

    func testUnmatchedRequirementsAreUntouched() {
        let rules = [feedback("CUDA", .neverCredit)]
        XCTAssertEqual(rules.verdict(forRequirement: "8 years of program management", jobNumber: 1), .none)
    }

    /// The commonest correction, and the mirror of `neverCredit`: the model found no evidence but
    /// the user has the experience. Job #93's "mentoring or coaching junior product owners" was a
    /// gap on the strength of the résumé not saying it explicitly.
    func testAlwaysCreditForcesMet() {
        let rules = [feedback("mentoring", .alwaysCredit)]
        XCTAssertEqual(
            rules.verdict(forRequirement: "Experience mentoring junior product owners", jobNumber: 1),
            .forceMet
        )
    }

    func testAlwaysCreditRemovesThePenalty() {
        let assessments: [[String: Any]] = [
            ["requirement": "Experience mentoring junior product owners", "status": "missing", "kind": "required"]
        ]
        XCTAssertEqual(FitScorer.requirementGaps(fromAssessments: assessments).count, 1, "penalised before")
        let gaps = FitScorer.requirementGaps(
            fromAssessments: assessments, feedback: [feedback("mentoring", .alwaysCredit)], jobNumber: 1
        )
        XCTAssertTrue(gaps.isEmpty)
    }

    /// Contradictory rules must not silently inflate: a confirmed absence outranks a confirmed
    /// presence, because suppressing a real gap is the more harmful error.
    func testNeverCreditBeatsAlwaysCredit() {
        let rules = [feedback("Kubernetes", .alwaysCredit), feedback("Kubernetes", .neverCredit)]
        XCTAssertEqual(rules.verdict(forRequirement: "Kubernetes in production", jobNumber: 1), .forceMissing)
    }

    // MARK: - Scope

    /// A one-off misread must not silently change every other job.
    func testJobSpecificFeedbackDoesNotLeak() {
        let rules = [feedback("stakeholder management", .jobSpecific, job: 42)]
        XCTAssertEqual(rules.verdict(forRequirement: "Strong stakeholder management", jobNumber: 42), .ignore)
        XCTAssertEqual(rules.verdict(forRequirement: "Strong stakeholder management", jobNumber: 99), .none)
    }

    func testGlobalFeedbackAppliesToEveryJob() {
        let rules = [feedback("PCI DSS", .neverCredit)]
        for job in [1, 2, 3] {
            XCTAssertEqual(rules.verdict(forRequirement: "PCI DSS experience", jobNumber: job), .forceMissing)
        }
    }

    /// Suppressing a real gap is worse than showing a spurious one, so a confirmed absence wins.
    func testForceMissingBeatsIgnoreWhenBothMatch() {
        let rules = [
            feedback("kubernetes", .notARequirement),
            feedback("Kubernetes", .neverCredit)
        ]
        XCTAssertEqual(
            rules.verdict(forRequirement: "Kubernetes in production", jobNumber: 1), .forceMissing
        )
    }

    func testMatchingIsCaseInsensitive() {
        let rules = [feedback("cuda", .neverCredit)]
        XCTAssertEqual(rules.verdict(forRequirement: "CUDA ecosystem", jobNumber: 1), .forceMissing)
    }

    func testEmptyPhrasesMatchNothing() {
        let rules = [feedback("   ", .neverCredit)]
        XCTAssertEqual(rules.verdict(forRequirement: "anything at all", jobNumber: 1), .none)
    }

    // MARK: - Effect on the score

    /// The point of the feature: a requirement the model called `met` becomes a penalised gap.
    func testANeverCreditRuleTurnsAMetRequirementIntoAPenalty() {
        let assessments: [[String: Any]] = [
            ["requirement": "Expertise in CUDA ecosystem", "status": "met", "kind": "required"]
        ]
        XCTAssertTrue(FitScorer.requirementGaps(fromAssessments: assessments).isEmpty, "no gap before")

        let gaps = FitScorer.requirementGaps(
            fromAssessments: assessments, feedback: [feedback("CUDA", .neverCredit)], jobNumber: 1
        )
        XCTAssertEqual(gaps.count, 1)
        XCTAssertEqual(gaps.first?.status, .missing)
        XCTAssertEqual(FitScorer.computeScore(dimensions: [:], gaps: gaps).penalty, 12)
    }

    func testANotARequirementRuleRemovesAnExistingPenalty() {
        let assessments: [[String: Any]] = [
            ["requirement": "Familiarity with Aha roadmapping", "status": "missing", "kind": "required"]
        ]
        XCTAssertEqual(FitScorer.requirementGaps(fromAssessments: assessments).count, 1, "penalised before")

        let gaps = FitScorer.requirementGaps(
            fromAssessments: assessments, feedback: [feedback("Aha", .notARequirement)], jobNumber: 1
        )
        XCTAssertTrue(gaps.isEmpty)
    }

    /// Corrections apply when gaps are rebuilt, so a recompute propagates them to stored scores with
    /// no LLM call — that's what makes the feature cheap to use and to undo.
    func testRecomputeAppliesFeedbackToAStoredScore() {
        let json = """
        {"dimensions":[{"name":"required_qualifications","score":90},
        {"name":"preferred_qualifications","score":90},{"name":"skills","score":90},
        {"name":"domain_fit","score":90},{"name":"experience_level","score":90}],
        "requirement_assessments":[
        {"requirement":"Expertise in CUDA ecosystem","status":"met","kind":"required"}]}
        """
        XCTAssertEqual(FitScorer.rescoreFromJSON(json)?.overall, 90)
        let corrected = FitScorer.rescoreFromJSON(
            json, feedback: [feedback("CUDA", .neverCredit)], jobNumber: 1
        )
        XCTAssertEqual(corrected?.penalty, 12)
        XCTAssertEqual(corrected?.overall, 78)
    }

    // MARK: - Round trip

    func testFeedbackSurvivesEncoding() throws {
        let original = ScoringFeedback(
            phrase: "electrical engineering", kind: .neverCredit, jobNumber: 231, note: "no EE background"
        )
        let data = try JSONEncoder().encode([original])
        let decoded = try JSONDecoder().decode([ScoringFeedback].self, from: data)
        XCTAssertEqual(decoded, [original])
    }

    /// The likeliest correction is offered first — a user looking at a gap usually means "I do have
    /// this", not the reverse.
    func testTheCommonestCorrectionIsListedFirst() {
        XCTAssertEqual(ScoringFeedback.Kind.allCases.first, .alwaysCredit)
    }

    func testEveryReasonHasUserFacingCopy() {
        for kind in ScoringFeedback.Kind.allCases {
            XCTAssertFalse(kind.label.isEmpty, kind.rawValue)
            XCTAssertFalse(kind.explanation.isEmpty, kind.rawValue)
        }
    }
}
