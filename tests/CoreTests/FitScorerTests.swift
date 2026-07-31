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
            ["requirement": "A", "kind": "required", "status": "met"],
            ["requirement": "B", "kind": "required", "status": "missing"],
            ["requirement": "C", "kind": "preferred", "status": "partial"]
        ]
        let gaps = FitScorer.requirementGaps(fromAssessments: assessments)
        XCTAssertEqual(gaps, [
            gap("B", .required, .missing),
            gap("C", .preferred, .partial)
        ])
    }

    func testRequirementGapsDefaultsKindToRequiredWhenAbsent() {
        let assessments: [[String: Any]] = [["requirement": "X", "status": "missing"]]
        let gaps = FitScorer.requirementGaps(fromAssessments: assessments)
        XCTAssertEqual(gaps, [gap("X", .required, .missing)])
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

    // MARK: - rescoreFromJSON

    func testRescoreFromJSON_usesStructuredAssessments() throws {
        // breakdown base: 80*.40 + 60*.20 + 80*.15 + 60*.15 + 100*.10 = 32+12+12+9+10 = 75
        // gaps: preferred/partial (5) + required/missing (12) = 17 → overall 58
        let json = """
        {
          "breakdown": {"required_qualifications": 80, "preferred_qualifications": 60,
                        "skills": 80, "domain_fit": 60, "experience_level": 100},
          "requirement_assessments": [
            {"requirement": "React", "kind": "preferred", "status": "partial"},
            {"requirement": "10y management", "kind": "required", "status": "missing"},
            {"requirement": "Swift", "kind": "required", "status": "met"}
          ]
        }
        """
        let result = try XCTUnwrap(FitScorer.rescoreFromJSON(json))
        XCTAssertEqual(result.penalty, 17)
        XCTAssertEqual(result.overall, 58)
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
