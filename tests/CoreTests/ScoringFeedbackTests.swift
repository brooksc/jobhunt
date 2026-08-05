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
        // 82, not the base 90: with one lone requirement the shrinkage prior still assumes a little
        // unevidenced risk (TASK-656). A realistic posting listing ten requirements, all met, loses
        // under 3 points.
        XCTAssertEqual(FitScorer.rescoreFromJSON(json)?.overall, 82)

        // Now the user says they don't have it: 1 of 1 required missed is a total failure against the
        // only stated requirement, so the penalty is severe rather than a flat 12.
        let corrected = FitScorer.rescoreFromJSON(
            json, feedback: [feedback("CUDA", .neverCredit)], jobNumber: 1
        )
        XCTAssertEqual(corrected?.penalty, 30)
        XCTAssertEqual(corrected?.overall, 60)
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

    // MARK: - Whole-word matching

    /// The production failure this replaced: `IDE`, captured from a job whose entire requirement text
    /// was "IDE", matched as a substring of ordinary words and force-credited 159 requirements across
    /// 120 of 415 jobs, inflating 28 scores by up to 34 points.
    func testShortPhraseDoesNotMatchInsideLongerWords() {
        for word in ["provide", "provider", "identify", "identity", "ideally", "alongside",
                     "considerations", "fidelity", "guide", "incident", "reside", "video"] {
            XCTAssertFalse(
                ScoringFeedback.matches(phrase: "IDE", in: "Experience with \(word) systems"),
                "'IDE' must not match inside '\(word)'"
            )
        }
    }

    /// ...while the rule still does the job the user flagged it for.
    func testShortPhraseStillMatchesTheWholeWord() {
        for text in ["IDE", "IDE integration", "Familiarity with the IDE.", "CLI/IDE tooling",
                     "experience with an ide"] {
            XCTAssertTrue(
                ScoringFeedback.matches(phrase: "IDE", in: text), "'IDE' should match in '\(text)'"
            )
        }
    }

    func testMatchingIsCaseInsensitiveAndTrimsThePhrase() {
        XCTAssertTrue(ScoringFeedback.matches(phrase: "  Kubernetes ", in: "Deep kubernetes experience"))
    }

    /// A phrase whose edge is punctuation must not demand a word boundary there — otherwise every
    /// correction captured from a full sentence stops matching.
    func testPunctuationAtThePhraseEdgeDoesNotBlockAMatch() {
        XCTAssertTrue(ScoringFeedback.matches(
            phrase: "Experience building AI agents.",
            in: "Experience building AI agents. Nice to have."
        ))
    }

    func testMultiWordPhrasesMatchOnWordBoundaries() {
        XCTAssertTrue(ScoringFeedback.matches(
            phrase: "electrical engineering", in: "Background in electrical engineering or controls"
        ))
        XCTAssertFalse(ScoringFeedback.matches(phrase: "art", in: "Partner with the smart team"))
    }

    func testVerdictUsesWholeWordMatching() {
        let rules = [feedback("IDE", .alwaysCredit)]
        XCTAssertEqual(
            rules.verdict(forRequirement: "Ability to provide guidance to engineers", jobNumber: 1), .none
        )
        XCTAssertEqual(rules.verdict(forRequirement: "IDE", jobNumber: 1), .forceMet)
    }

    // MARK: - Authoring-time validation

    func testTooShortPhrasesAreRejectedWhenAuthored() {
        XCTAssertNotNil(ScoringFeedback.rejectionReason(forPhrase: "AI"))
        XCTAssertNotNil(ScoringFeedback.rejectionReason(forPhrase: "   "))
        XCTAssertNotNil(ScoringFeedback.rejectionReason(forPhrase: "--"))
    }

    func testUsablePhrasesAreAccepted() {
        for phrase in ["IDE", "CUDA", "electrical engineering", "Kubernetes"] {
            XCTAssertNil(ScoringFeedback.rejectionReason(forPhrase: phrase), phrase)
        }
    }

    // MARK: - Match counts (orphan detection)

    /// A correction that has stopped matching anything is invisible without this: three of the six
    /// live rules were orphaned by a re-score rewording their requirement, and kept "applying" to
    /// nothing while the user believed they were in force.
    func testMatchCountsExposeOrphanedAndOverBroadRules() async throws {
        let container = try ModelContainerFactory.inMemory()
        let store = BackgroundStore(modelContainer: container)
        let job = Job(id: UUID().uuidString, jobNumber: 732, company: "Docker")
        try await store.insert(job)
        let resume = Resume(name: "R", text: "x", charCount: 1, active: true, sortOrder: 0)
        try await store.insert(resume)
        let json = """
        {"requirement_assessments":[
          {"requirement":"IDE","kind":"preferred","status":"missing","evidence":""},
          {"requirement":"Ability to provide guidance","kind":"required","status":"met","evidence":""},
          {"requirement":"Experience with CUDA kernels","kind":"required","status":"missing","evidence":""}
        ]}
        """
        try await store.saveFitScore(
            jobID: job.id, resumeID: resume.id, overall: 50, fitJSON: json, model: nil, scoredAt: Date()
        )

        let live = feedback("IDE", .alwaysCredit)
        let orphan = feedback("Experience building AI agents.", .alwaysCredit)
        let counts = try await store.scoringFeedbackMatchCounts([live, orphan])

        // "IDE" matches only the standalone requirement, not "provide".
        XCTAssertEqual(counts[live.id], 1)
        // The orphaned rule matches nothing and is reported as such rather than silently absent.
        XCTAssertEqual(counts[orphan.id], 0)
    }

    func testJobSpecificRulesOnlyCountAgainstTheirOwnJob() async throws {
        let container = try ModelContainerFactory.inMemory()
        let store = BackgroundStore(modelContainer: container)
        let job = Job(id: UUID().uuidString, jobNumber: 1, company: "A")
        try await store.insert(job)
        let resume = Resume(name: "R", text: "x", charCount: 1, active: true, sortOrder: 0)
        try await store.insert(resume)
        let json = """
        {"requirement_assessments":[{"requirement":"Kubernetes","kind":"required","status":"missing","evidence":""}]}
        """
        try await store.saveFitScore(
            jobID: job.id, resumeID: resume.id, overall: 50, fitJSON: json, model: nil, scoredAt: Date()
        )

        let elsewhere = ScoringFeedback(phrase: "Kubernetes", kind: .jobSpecific, jobNumber: 999)
        let here = ScoringFeedback(phrase: "Kubernetes", kind: .jobSpecific, jobNumber: 1)
        let counts = try await store.scoringFeedbackMatchCounts([elsewhere, here])
        XCTAssertEqual(counts[elsewhere.id], 0)
        XCTAssertEqual(counts[here.id], 1)
    }
}
