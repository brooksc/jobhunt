import XCTest
@testable import JobhuntCore

final class FitScorerTests: XCTestCase {
    // MARK: - Helpers

    /// Build a full-weight dimension set with each value = score.
    private func allDimensions(_ score: Double) -> [String: Double] {
        [
            "required_qualifications": score,
            "preferred_qualifications": score,
            "skills": score,
            "experience_level": score,
            "domain_fit": score
        ]
    }

    private func gap(
        _ requirement: String,
        _ kind: FitScorer.RequirementGap.Kind,
        _ status: FitScorer.RequirementGap.Status
    ) -> FitScorer.RequirementGap {
        .init(requirement: requirement, kind: kind, status: status)
    }

    // MARK: - Weight constants (TASK-602)

    func testWeightsTotalOne() {
        let total = FitScorer.dimensionWeights.values.reduce(0, +)
        XCTAssertEqual(total, 1.0, accuracy: 1e-9)
    }

    func testExpectedWeights() {
        XCTAssertEqual(FitScorer.dimensionWeights["required_qualifications"], 0.40)
        XCTAssertEqual(FitScorer.dimensionWeights["preferred_qualifications"], 0.20)
        XCTAssertEqual(FitScorer.dimensionWeights["skills"], 0.15)
        XCTAssertEqual(FitScorer.dimensionWeights["domain_fit"], 0.15)
        XCTAssertEqual(FitScorer.dimensionWeights["experience_level"], 0.10)
    }

    // MARK: - Weighted score (no penalty)

    func testPerfectScore() {
        let result = FitScorer.computeScore(dimensions: allDimensions(100))
        XCTAssertEqual(result.overall, 100)
        XCTAssertEqual(result.penalty, 0)
    }

    func testZeroScore() {
        XCTAssertEqual(FitScorer.computeScore(dimensions: allDimensions(0)).overall, 0)
    }

    func testMidpointScore() {
        // All dimensions = 50 → weighted sum = 50 * 1.0 = 50
        XCTAssertEqual(FitScorer.computeScore(dimensions: allDimensions(50)).overall, 50)
    }

    func testHeterogeneousWeightedScore() {
        // required=80, preferred=60, skills=70, experience=90, domain=50
        // weighted = 80*0.40 + 60*0.20 + 70*0.15 + 90*0.10 + 50*0.15
        //          = 32 + 12 + 10.5 + 9 + 7.5 = 71
        let dims: [String: Double] = [
            "required_qualifications": 80,
            "preferred_qualifications": 60,
            "skills": 70,
            "experience_level": 90,
            "domain_fit": 50
        ]
        let result = FitScorer.computeScore(dimensions: dims)
        XCTAssertEqual(result.overall, 71)
        XCTAssertEqual(result.penalty, 0)
    }

    func testPartialDimensionsNormalized() {
        // Only required_qualifications supplied with score 100; missing dimensions score 0.
        // weightedSum = 100 * 0.40 = 40, totalWeight = 1.0 → baseScore = 40
        XCTAssertEqual(FitScorer.computeScore(dimensions: ["required_qualifications": 100]).overall, 40)
    }

    func testMissingOneDimension_lowerThanFull() {
        var partial = allDimensions(100)
        partial.removeValue(forKey: "domain_fit") // weight 0.15
        // weightedSum = 100 * 0.85 = 85
        let result = FitScorer.computeScore(dimensions: partial)
        XCTAssertEqual(result.overall, 85)
        XCTAssertLessThan(result.overall, 100)
    }

    func testAllDimensionsMissing_scoreIsZero() {
        XCTAssertEqual(FitScorer.computeScore(dimensions: [:]).overall, 0)
    }

    // MARK: - Penalty grid (kind × status), TASK-602

    func testPenaltyPointsGrid() {
        XCTAssertEqual(FitScorer.penaltyPoints(kind: .required, status: .missing), 12)
        XCTAssertEqual(FitScorer.penaltyPoints(kind: .required, status: .partial), 6)
        XCTAssertEqual(FitScorer.penaltyPoints(kind: .preferred, status: .missing), 10)
        XCTAssertEqual(FitScorer.penaltyPoints(kind: .preferred, status: .partial), 5)
    }

    func testEachGapKindStatusAppliesItsCost() {
        let cases: [(FitScorer.RequirementGap.Kind, FitScorer.RequirementGap.Status, Int)] = [
            (.required, .missing, 12), (.required, .partial, 6),
            (.preferred, .missing, 10), (.preferred, .partial, 5)
        ]
        for (kind, status, cost) in cases {
            let r = FitScorer.computeScore(dimensions: allDimensions(100), gaps: [gap("x", kind, status)])
            XCTAssertEqual(r.penalty, cost, "\(kind)/\(status) should cost \(cost)")
            XCTAssertEqual(r.overall, 100 - cost)
        }
    }

    func testMixedGapsSum() {
        // 12 (req/missing) + 5 (pref/partial) + 10 (pref/missing) = 27
        let gaps = [
            gap("must-have A", .required, .missing),
            gap("nice B", .preferred, .partial),
            gap("nice C", .preferred, .missing)
        ]
        let result = FitScorer.computeScore(dimensions: allDimensions(100), gaps: gaps)
        XCTAssertEqual(result.penalty, 27)
        XCTAssertEqual(result.overall, 73)
    }

    func testPenaltyCappedAt60() {
        // 6 × required/missing (12) = 72 → capped at 60
        let gaps = (0 ..< 6).map { gap("req \($0)", .required, .missing) }
        XCTAssertEqual(FitScorer.computeScore(dimensions: allDimensions(100), gaps: gaps).penalty, 60)
    }

    func testOverallFlooredAtZero() {
        let gaps = (0 ..< 6).map { gap("req \($0)", .required, .missing) } // 60 penalty
        let result = FitScorer.computeScore(dimensions: allDimensions(10), gaps: gaps)
        XCTAssertEqual(result.overall, 0)
    }

    func testNoPenaltyWhenNoGaps() {
        let result = FitScorer.computeScore(dimensions: allDimensions(80), gaps: [])
        XCTAssertEqual(result.penalty, 0)
        XCTAssertEqual(result.overall, 80)
    }

    func testPenaltyReasonsCiteRequirementKindStatus() {
        let result = FitScorer.computeScore(
            dimensions: allDimensions(80),
            gaps: [gap("Terraform experience", .preferred, .missing)]
        )
        XCTAssertEqual(result.penaltyReasons.count, 1)
        let reason = try? XCTUnwrap(result.penaltyReasons.first)
        XCTAssertTrue(reason?.contains("Terraform experience") == true)
        XCTAssertTrue(reason?.contains("preferred") == true)
        XCTAssertTrue(reason?.contains("missing") == true)
    }

    // MARK: - requirementGaps(fromAssessments:)

    func testRequirementGapsSkipsMetKeepsPartialAndMissing() {
        let assessments: [[String: Any]] = [
            ["requirement": "8 years of program management", "kind": "required", "status": "met"],
            ["requirement": "Experience with distributed systems", "kind": "required", "status": "missing"],
            ["requirement": "Experience in healthcare", "kind": "preferred", "status": "partial"]
        ]
        let gaps = FitScorer.requirementGaps(fromAssessments: assessments)
        XCTAssertEqual(gaps, [
            gap("Experience with distributed systems", .required, .missing),
            gap("Experience in healthcare", .preferred, .partial)
        ])
    }

    func testRequirementGapsDefaultsKindToRequiredWhenAbsent() {
        let assessments: [[String: Any]] = [["requirement": "Experience with Kubernetes", "status": "missing"]]
        let gaps = FitScorer.requirementGaps(fromAssessments: assessments)
        XCTAssertEqual(gaps, [gap("Experience with Kubernetes", .required, .missing)])
    }

    // MARK: - Breakdown / weights in result

    func testBreakdownContainsAllDimensionsClamped() {
        let over = FitScorer.computeScore(dimensions: allDimensions(150))
        let under = FitScorer.computeScore(dimensions: allDimensions(-10))
        for key in FitScorer.dimensionWeights.keys {
            XCTAssertNotNil(over.breakdown[key])
            XCTAssertLessThanOrEqual(over.breakdown[key] ?? 0, 100)
            XCTAssertGreaterThanOrEqual(under.breakdown[key] ?? -1, 0)
        }
    }

    func testResultContainsScoreWeights() {
        let result = FitScorer.computeScore(dimensions: allDimensions(80))
        XCTAssertEqual(result.scoreWeights["required_qualifications"], 0.40)
        XCTAssertEqual(result.scoreWeights.count, FitScorer.dimensionWeights.count)
    }

    // MARK: - Normalised penalty (TASK-656)

    private func assessments(required: [String], preferred: [String]) -> [[String: Any]] {
        required.enumerated().map { ["requirement": "Experience with req\($0.offset)", "kind": "required", "status": $0.element] }
            + preferred.enumerated().map {
                ["requirement": "Experience with pref\($0.offset)", "kind": "preferred", "status": $0.element]
            }
    }

    private func score(required: [String], preferred: [String], base: Double = 85) -> FitScoreResult {
        let a = assessments(required: required, preferred: preferred)
        return FitScorer.computeScore(
            dimensions: allDimensions(base),
            gaps: FitScorer.requirementGaps(fromAssessments: a),
            counts: FitScorer.requirementCounts(fromAssessments: a)
        )
    }

    /// The defect that motivated the change: job #734 met every required qualification and scored 0,
    /// because missing nice-to-haves alone exhausted the old 60-point cap.
    func testPreferredGapsAloneCannotZeroAJobThatMeetsEveryRequirement() {
        let result = score(
            required: Array(repeating: "met", count: 6),
            preferred: Array(repeating: "missing", count: 8)
        )
        XCTAssertGreaterThan(result.overall, 60, "preferred-only gaps must not sink a fully-qualified match")
        XCTAssertLessThan(result.penalty, 15, "nice-to-haves are a tiebreaker, not a disqualifier")
    }

    /// A missing hard requirement has to outweigh a missing nice-to-have by a wide margin. Compare
    /// *marginal* cost: both scenarios also carry the small shrinkage floor, so comparing raw totals
    /// understates the difference.
    func testAMissingRequiredCostsFarMoreThanAMissingPreferred() {
        let allMet = score(required: ["met", "met", "met"], preferred: ["met"])
        let missingRequired = score(required: ["met", "met", "missing"], preferred: ["met"])
        let missingPreferred = score(required: ["met", "met", "met"], preferred: ["missing"])

        let requiredCost = missingRequired.penalty - allMet.penalty
        let preferredCost = missingPreferred.penalty - allMet.penalty
        XCTAssertGreaterThan(requiredCost, preferredCost * 2,
                             "required \(requiredCost) vs preferred \(preferredCost)")
    }

    /// A verbose posting was arithmetically guaranteed to saturate under the old raw sum: 10 missing
    /// requirements cost 120 points and pinned the cap regardless of fit. Penalty now converges on the
    /// *share* missed, so listing more requirements at the same 50% miss rate costs a bounded amount
    /// more — reflecting greater confidence — rather than growing without limit.
    func testAVerbosePostingIsNotPunishedForVerbosity() {
        let short = score(required: ["met", "missing"], preferred: [])
        let long = score(required: Array(repeating: "met", count: 10) + Array(repeating: "missing", count: 10),
                         preferred: [])

        // Both sit near 65 * 0.5, and nowhere near the old capped 60.
        XCTAssertLessThan(long.penalty, 40)
        XCTAssertLessThan(long.penalty - short.penalty, 15,
                          "10x the requirements at the same miss rate must not multiply the penalty")
        XCTAssertGreaterThan(long.penalty, short.penalty,
                             "more evidence of missing should still count for something")
    }

    /// No cap means no flat region where the score stops responding to additional gaps.
    func testScoreKeepsRespondingAsGapsAccumulate() {
        let scores = (0 ... 8).map { missing in
            score(required: Array(repeating: "missing", count: missing)
                + Array(repeating: "met", count: 8 - missing), preferred: []).overall
        }
        for (a, b) in zip(scores, scores.dropFirst()) {
            XCTAssertGreaterThan(a, b, "each additional missing requirement must still move the score")
        }
    }

    /// Bounded by construction rather than by a cap: required 65 + preferred 12.
    func testPenaltyIsBoundedWithoutACap() {
        let worst = score(required: Array(repeating: "missing", count: 20),
                          preferred: Array(repeating: "missing", count: 20))
        XCTAssertLessThanOrEqual(worst.penalty, 77)
        XCTAssertGreaterThan(worst.penalty, 60, "a total failure should exceed the old cap")
    }

    /// Legacy rows stored only `requirements_not_met` strings, so there's no denominator to normalise
    /// by; those must keep the old additive-and-capped behaviour rather than silently rescoring.
    func testLegacyScoresWithoutCountsKeepTheCappedAdditiveModel() {
        let gaps = (0 ..< 20).map {
            FitScorer.RequirementGap(requirement: "r\($0)", kind: .required, status: .missing)
        }
        let result = FitScorer.computeScore(dimensions: allDimensions(100), gaps: gaps)
        XCTAssertEqual(result.penalty, FitScorer.penaltyCap)
    }

    // MARK: - rescoreFromJSON

    func testRescoreFromJSON_usesStructuredAssessments() throws {
        // breakdown base: 80*.40 + 60*.20 + 80*.15 + 60*.15 + 100*.10 = 32+12+12+9+10 = 75
        // Penalty is the SHARE of each tier that's unmet (TASK-656), not a per-gap sum:
        //   required:  1 of 2 missed → (1.0 + 2*0.184)/(2+2) = 0.342 → 65 * 0.342 = 22.2
        //   preferred: 1 of 1 partial → (0.5 + 0.368)/(1+2)  = 0.289 → 12 * 0.289 =  3.5
        // → 26, overall 49. Missing half the required qualifications costs far more than the old
        // flat 12 did, which is the point.
        let json = """
        {
          "breakdown": {"required_qualifications": 80, "preferred_qualifications": 60,
                        "skills": 80, "domain_fit": 60, "experience_level": 100},
          "requirement_assessments": [
            {"requirement": "Strong React knowledge", "kind": "preferred", "status": "partial"},
            {"requirement": "10+ years of management experience", "kind": "required", "status": "missing"},
            {"requirement": "Deep Swift knowledge", "kind": "required", "status": "met"}
          ]
        }
        """
        let result = try XCTUnwrap(FitScorer.rescoreFromJSON(json))
        XCTAssertEqual(result.penalty, 26)
        XCTAssertEqual(result.overall, 49)
    }

    func testRescoreFromJSON_legacyArrayFormat_treatedAsRequiredMissing() throws {
        // No assessments → legacy requirements_not_met treated as missing REQUIRED gaps (12 each).
        // dims: 80,60,75,70,65 → 80*.40 + 60*.20 + 75*.15 + 70*.10 + 65*.15
        //     = 32 + 12 + 11.25 + 7 + 9.75 = 72 ; penalty 12 → overall 60
        let legacyJSON = """
        {
            "requirements_not_met": ["5+ years managing teams"],
            "dimensions": [
                {"name": "required_qualifications", "score": 80, "rationale": "x"},
                {"name": "preferred_qualifications", "score": 60, "rationale": "x"},
                {"name": "skills", "score": 75, "rationale": "x"},
                {"name": "experience_level", "score": 70, "rationale": "x"},
                {"name": "domain_fit", "score": 65, "rationale": "x"}
            ]
        }
        """
        let result = try XCTUnwrap(FitScorer.rescoreFromJSON(legacyJSON))
        XCTAssertEqual(result.penalty, 12)
        XCTAssertEqual(result.overall, 60)
    }

    func testRescoreFromJSONInvalidReturnsNil() {
        XCTAssertNil(FitScorer.rescoreFromJSON("not json"))
        XCTAssertNil(FitScorer.rescoreFromJSON("{}"))
        XCTAssertNil(FitScorer.rescoreFromJSON("{\"dimensions\": []}"))
    }

    // MARK: - encode / decode round trip

    func testEncodeDecodeRoundTrip() throws {
        let result = FitScorer.computeScore(
            dimensions: allDimensions(85),
            gaps: [gap("RTL design", .required, .missing), gap("Java", .preferred, .partial)]
        )
        let json = try XCTUnwrap(FitScorer.encode(result))
        let decoded = try XCTUnwrap(FitScorer.decode(from: json))
        XCTAssertEqual(decoded.overall, result.overall)
        XCTAssertEqual(decoded.penalty, result.penalty)
        XCTAssertEqual(decoded.penaltyReasons, result.penaltyReasons)
        XCTAssertEqual(decoded.breakdown.count, result.breakdown.count)
    }

    // MARK: - TASK-453: dimension contract validation (unchanged)

    private func validDims() -> [[String: Any]] {
        [
            ["name": "required_qualifications", "score": 80],
            ["name": "preferred_qualifications", "score": 60],
            ["name": "skills", "score": 70],
            ["name": "experience_level", "score": 90],
            ["name": "domain_fit", "score": 50]
        ]
    }

    func testValidateDimensions_validReturnsAllFive() throws {
        let dims = try FitScorer.validateDimensions(validDims())
        XCTAssertEqual(dims.count, 5)
        XCTAssertEqual(dims["required_qualifications"], 80)
        XCTAssertEqual(dims["domain_fit"], 50)
    }

    func testValidateDimensions_unknownNameThrows() {
        var d = validDims(); d.append(["name": "Technical", "score": 75])
        XCTAssertThrowsError(try FitScorer.validateDimensions(d)) {
            XCTAssertEqual($0 as? FitScorer.FitDimensionError, .unknown("Technical"))
        }
    }

    func testValidateDimensions_missingDimensionThrows() {
        var d = validDims(); d.removeLast() // drop domain_fit
        XCTAssertThrowsError(try FitScorer.validateDimensions(d)) {
            XCTAssertEqual($0 as? FitScorer.FitDimensionError, .missing(["domain_fit"]))
        }
    }

    func testValidateDimensions_duplicateThrows() {
        var d = validDims(); d.append(["name": "skills", "score": 10])
        XCTAssertThrowsError(try FitScorer.validateDimensions(d)) {
            XCTAssertEqual($0 as? FitScorer.FitDimensionError, .duplicate("skills"))
        }
    }

    func testValidateDimensions_nonNumericScoreThrows() {
        var d = validDims(); d[0] = ["name": "required_qualifications", "score": "high"]
        XCTAssertThrowsError(try FitScorer.validateDimensions(d)) {
            XCTAssertEqual($0 as? FitScorer.FitDimensionError, .nonNumericScore("required_qualifications"))
        }
    }
}

// MARK: - Assessment prompt version

/// Tightening what counts as "met" makes new scores stricter than the 171 already stored, and a
/// recompute can't reconcile them — the arithmetic is unchanged, it's the model's judgment that
/// moved. Without a stamp, a `min_score` filter silently compares two different measurements.
final class AssessmentPromptVersionTests: XCTestCase {
    private func merged(_ raw: [String: Any]) throws -> [String: Any] {
        let result = FitScorer.computeScore(dimensions: [:], gaps: [])
        let json = try XCTUnwrap(FitScorer.buildMergedJSON(result: result, rawLLMDict: raw))
        let data = try XCTUnwrap(json.data(using: .utf8))
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    /// A fresh assessment carries whatever version the caller stamped.
    func testAFreshAssessmentKeepsTheStampedVersion() throws {
        let out = try merged(["assessment_prompt_version": FitScorer.assessmentPromptVersion])
        XCTAssertEqual(out["assessment_prompt_version"] as? Int, FitScorer.assessmentPromptVersion)
    }

    /// Recompute re-runs the arithmetic over an OLD judgment, so it must not relabel it as current —
    /// that would erase exactly the distinction the stamp exists to preserve.
    func testRecomputePreservesAnOlderVersionRatherThanRelabelling() throws {
        let out = try merged(["assessment_prompt_version": 1, "dimensions": []])
        XCTAssertEqual(out["assessment_prompt_version"] as? Int, 1)
    }

    /// Scores stored before the stamp existed are v1 by definition.
    func testUnstampedLegacyScoresDefaultToVersionOne() throws {
        let out = try merged(["dimensions": []])
        XCTAssertEqual(out["assessment_prompt_version"] as? Int, 1)
    }

    func testVersionIsAheadOfLegacy() {
        XCTAssertGreaterThan(FitScorer.assessmentPromptVersion, 1)
    }
}

// MARK: - Recompute refuses an incomplete dimension set

/// `computeScore` scores a missing dimension as 0, which is right when validating a live response —
/// a partial answer must not inflate — but wrong on recompute. Recompute is advertised as free and
/// safe, so a stored score missing one dimension would quietly lose up to 40 points on an operation
/// the user was told just re-runs the arithmetic. The live path already rejects these.
final class RescoreDimensionValidationTests: XCTestCase {
    private func json(dimensions: [String: Double]) -> String {
        let arr = dimensions.map { ["name": $0.key, "score": $0.value] as [String: Any] }
        let data = (try? JSONSerialization.data(withJSONObject: ["dimensions": arr])) ?? Data()
        return String(data: data, encoding: .utf8) ?? "{}"
    }

    private var complete: [String: Double] {
        [
            "required_qualifications": 90,
            "preferred_qualifications": 85,
            "skills": 90,
            "domain_fit": 90,
            "experience_level": 95
        ]
    }

    func testACompleteSetRescoresNormally() {
        let result = FitScorer.rescoreFromJSON(json(dimensions: complete))
        XCTAssertEqual(result?.overall, 90, "base with no gaps")
    }

    /// The reported risk: dropping domain_fit is a silent −13.5 without this guard.
    func testAnIncompleteSetIsRefusedRatherThanScoredAsZero() {
        var partial = complete
        partial.removeValue(forKey: "domain_fit")
        XCTAssertNil(
            FitScorer.rescoreFromJSON(json(dimensions: partial)),
            "an incomplete set must leave the stored score untouched, not deflate it"
        )
    }

    func testEveryMissingDimensionIsCaught() {
        for name in FitScorer.dimensionWeights.keys {
            var partial = complete
            partial.removeValue(forKey: name)
            XCTAssertNil(FitScorer.rescoreFromJSON(json(dimensions: partial)), "missing \(name)")
        }
    }

    func testAnEmptySetIsStillRefused() {
        XCTAssertNil(FitScorer.rescoreFromJSON(json(dimensions: [:])))
    }

    /// Extra dimensions beyond the expected set don't make it incomplete.
    func testUnknownExtraDimensionsDoNotBlockRescore() {
        var extra = complete
        extra["some_future_dimension"] = 50
        XCTAssertNotNil(FitScorer.rescoreFromJSON(json(dimensions: extra)))
    }
}

// MARK: - base score is one implementation

/// Reporting "90 base, −16 penalty" means two places need the base. When the projection layer
/// reimplemented the weighted sum it disagreed with the scorer on the first real job: summing the
/// weights in dictionary order made 89.5 / 1.0000000000000002 round to 89 instead of 90.
final class BaseScoreTests: XCTestCase {
    /// The exact Akamai #607 breakdown that exposed the divergence.
    private let breakdown: [String: Double] = [
        "required_qualifications": 90, "preferred_qualifications": 85,
        "skills": 90, "domain_fit": 90, "experience_level": 95
    ]

    func testBaseMatchesTheReportedCase() {
        XCTAssertEqual(FitScorer.baseScore(breakdown: breakdown), 90, "89.5 must round to 90, not 89")
    }

    /// The property that matters: base and overall must agree whenever the score didn't floor.
    func testBasePlusPenaltyReconstructsTheOverall() {
        let gaps = [
            FitScorer.RequirementGap(requirement: "a", kind: .required, status: .partial),
            FitScorer.RequirementGap(requirement: "b", kind: .preferred, status: .partial),
            FitScorer.RequirementGap(requirement: "c", kind: .preferred, status: .partial)
        ]
        let result = FitScorer.computeScore(dimensions: breakdown, gaps: gaps)
        XCTAssertEqual(result.overall, 74)
        XCTAssertEqual(FitScorer.baseScore(breakdown: result.breakdown), result.overall + result.penalty)
    }

    /// …and why the base can't just be derived as overall + penalty: the overall floors at 0.
    func testBaseIsNotRecoverableFromAFlooredOverall() {
        let low = [
            "required_qualifications": 20.0,
            "preferred_qualifications": 20,
            "skills": 20,
            "domain_fit": 20,
            "experience_level": 20
        ]
        let gaps = (0 ..< 6).map {
            FitScorer.RequirementGap(requirement: "g\($0)", kind: .required, status: .missing)
        }
        let result = FitScorer.computeScore(dimensions: low, gaps: gaps)
        XCTAssertEqual(result.overall, 0, "floored")
        XCTAssertEqual(FitScorer.baseScore(breakdown: result.breakdown), 20)
        XCTAssertNotEqual(result.overall + result.penalty, 20, "overall+penalty would misreport it")
    }

    func testAnEmptyBreakdownScoresZeroRatherThanCrashing() {
        XCTAssertEqual(FitScorer.baseScore(breakdown: [:]), 0)
    }
}

// MARK: - Non-discriminating requirements

/// Job #718 lost 6 points to "Experience with, or capacity to learn, JIRA, Confluence, and Aha" —
/// a requirement satisfied by anyone. The gap was manufactured by the named-technology rule itself:
/// JIRA is a named tool the résumé doesn't mention, so it scored partial.
///
/// Filtered in code rather than by prompt. Telling gemini-3.1-flash-lite to "omit" this class made
/// things markedly worse — it scored the items met instead of omitting them, and the extra rule
/// diluted the ones that worked (#231 regressed from a correct 60 back to 96).
final class NonDiscriminatingRequirementTests: XCTestCase {
    func testTheReportedCaseIsFiltered() {
        XCTAssertTrue(FitScorer.isNonDiscriminating(
            requirement: "Experience with, or capacity to learn, JIRA, Confluence, and Aha"
        ))
    }

    func testAptitudeEscapeClausesAreFiltered() {
        for text in [
            "Willingness to learn new frameworks",
            "Ability to learn our internal tooling quickly",
            "Experience with Kubernetes or eagerness to learn it"
        ] {
            XCTAssertTrue(FitScorer.isNonDiscriminating(requirement: text), text)
        }
    }

    func testValuesAlignmentIsFiltered() {
        for text in ["Alignment with Zip's core values", "Strong cultural fit", "Passion for our mission"] {
            XCTAssertTrue(FitScorer.isNonDiscriminating(requirement: text), text)
        }
    }

    /// The narrowness that matters: the filter targets the ESCAPE CLAUSE, not the skill. Dropping
    /// real tool requirements would hide genuine gaps.
    func testRealRequirementsAreNotFiltered() {
        for text in [
            "Experience with JIRA, Confluence, and Aha",
            "5+ years of Kubernetes in production",
            "Exceptional written and verbal communication skills",
            "Ability to influence stakeholders at all levels",
            "Ability to navigate ambiguity"
        ] {
            XCTAssertFalse(FitScorer.isNonDiscriminating(requirement: text), text)
        }
    }

    /// The behaviour that fixes #718: no penalty, without pretending the item was met.
    func testAFilteredRequirementCostsNoPenalty() {
        let assessments: [[String: Any]] = [
            ["requirement": "Experience with, or capacity to learn, JIRA", "status": "partial", "kind": "required"],
            ["requirement": "5+ years of Kubernetes in production", "status": "partial", "kind": "required"]
        ]
        let gaps = FitScorer.requirementGaps(fromAssessments: assessments)
        XCTAssertEqual(gaps.count, 1, "only the real gap survives")
        XCTAssertEqual(gaps.first?.requirement, "5+ years of Kubernetes in production")
        XCTAssertEqual(FitScorer.computeScore(dimensions: [:], gaps: gaps).penalty, 6)
    }

    /// Filtering happens when gaps are built, so a recompute applies it to already-stored scores
    /// for free — no re-scoring cost.
    func testRecomputeAppliesTheFilterToStoredScores() {
        let json = """
        {"dimensions":[{"name":"required_qualifications","score":90},
        {"name":"preferred_qualifications","score":90},{"name":"skills","score":90},
        {"name":"domain_fit","score":90},{"name":"experience_level","score":90}],
        "requirement_assessments":[
        {"requirement":"Experience with, or capacity to learn, JIRA","status":"missing","kind":"required"}]}
        """
        let result = FitScorer.rescoreFromJSON(json)
        XCTAssertEqual(result?.penalty, 0, "the invented gap must not survive a recompute")
        XCTAssertEqual(result?.overall, 90)
    }
}

/// The gap LIST, not just the penalty. A zero-cost gap still reads as something to fix — which is
/// how job #718 surfaced: "Experience with, or capacity to learn, JIRA, Confluence, and Aha" sat
/// under Gaps with a warning icon.
final class NonDiscriminatingProjectionTests: XCTestCase {
    private func projection(_ requirements: [(String, String)]) -> FitScoreProjection {
        let assessments = requirements.map {
            ["requirement": $0.0, "status": $0.1, "kind": "required", "evidence": ""] as [String: Any]
        }
        let json = (try? JSONSerialization.data(withJSONObject: ["requirement_assessments": assessments]))
            .flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
        let record = JobFitScore()
        record.fitScoreJSON = json
        return FitScoreProjection(fitScore: record)
    }

    func testAFilteredRequirementDoesNotAppearAsAGap() {
        let p = projection([
            ("Experience with, or capacity to learn, JIRA, Confluence, and Aha", "partial"),
            ("5+ years of Kubernetes in production", "partial")
        ])
        XCTAssertEqual(p.requirementsNotMet, ["5+ years of Kubernetes in production"])
        XCTAssertFalse(p.requirementAssessments.contains { $0.requirement.contains("JIRA") })
    }

    /// …and it isn't quietly recorded as met either — it simply isn't a requirement.
    func testAFilteredRequirementIsNotCountedAsMet() {
        let p = projection([("Alignment with Acme's core values", "met")])
        XCTAssertTrue(p.requirementsMet.isEmpty)
        XCTAssertTrue(p.requirementAssessments.isEmpty)
    }

    func testRealGapsStillSurface() {
        let p = projection([("Experience with JIRA, Confluence, and Aha", "missing")])
        XCTAssertEqual(p.requirementsNotMet.count, 1)
    }
}

/// Fragment requirements — bare noun phrases the extractor sliced out of a list.
///
/// The largest single source of spurious penalty measured on the real corpus: 34.9% of preferred
/// requirements, 20.3% of all penalty points, and 42% of the jobs pinned at the old cap. The
/// predicate here is a port of the one used for that measurement
/// (`scripts/analyze-fit-quality.py:is_fragment`) — if the two drift, the shipped filter stops
/// matching the numbers it was justified by.
final class FragmentRequirementTests: XCTestCase {
    /// #732's root cause: `preferred[20]` whose entire text was "IDE".
    func testBareNounPhrasesAreFragments() {
        for text in ["IDE", "Governance", "Partners", "CLI", "Data pipelines", "Product strategy"] {
            XCTAssertTrue(FitScorer.isFragment(requirement: text), text)
        }
    }

    /// Terse but assessable — a credential or a duration is a real requirement however short.
    func testCredentialsAndDurationsAreKept() {
        for text in ["5+ years", "BS degree", "MBA preferred", "PhD required", "Bachelor's in CS"] {
            XCTAssertFalse(FitScorer.isFragment(requirement: text), text)
        }
    }

    /// So is anything framed as experience or proficiency, even in three words.
    func testExperienceFramingIsKept() {
        for text in ["Strong Python knowledge", "Proven leadership", "Kubernetes experience", "Familiar with Terraform"] {
            XCTAssertFalse(FitScorer.isFragment(requirement: text), text)
        }
    }

    /// Inflections count. Matching these as whole words discarded "Familiarity with Salesforce" while
    /// keeping "Familiar with Salesforce" — found by checking the filter against hand labels, where
    /// the labeller had judged it a real requirement and met.
    func testInflectedProficiencyWordsAreKept() {
        for text in [
            "Familiarity with Salesforce", "Experienced in Rust", "Proficiency in SQL",
            "Excellent communication", "Ability to influence", "Expertise in Kafka"
        ] {
            XCTAssertFalse(FitScorer.isFragment(requirement: text), text)
        }
    }

    /// Anything longer than three words has enough to assess.
    func testLongerRequirementsAreNeverFragments() {
        for text in [
            "Deploy and operate services on Kubernetes",
            "Work with partners across the organisation to land roadmaps"
        ] {
            XCTAssertFalse(FitScorer.isFragment(requirement: text), text)
        }
    }

    /// The behaviour that matters: a fragment leaves BOTH the numerator and the denominator, so it
    /// can't depress the score by sitting in the count of things to satisfy.
    func testFragmentsLeaveTheDenominatorToo() {
        let assessments: [[String: Any]] = [
            ["requirement": "IDE", "status": "missing", "kind": "preferred"],
            ["requirement": "Governance", "status": "missing", "kind": "preferred"],
            ["requirement": "5+ years of Kubernetes in production", "status": "met", "kind": "required"]
        ]
        let counts = FitScorer.requirementCounts(fromAssessments: assessments)
        XCTAssertEqual(counts.preferred, 0)
        XCTAssertEqual(counts.required, 1)
        XCTAssertTrue(FitScorer.requirementGaps(fromAssessments: assessments).isEmpty)
        XCTAssertEqual(
            FitScorer.verdictShare(assessments: assessments, partialCredit: 0.5), 100,
            "the one real requirement is met, so the share is 100 — fragments must not dilute it"
        )
    }
}
