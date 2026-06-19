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

    // MARK: - Weight constants

    func testWeightsTotalOne() {
        let total = FitScorer.dimensionWeights.values.reduce(0, +)
        XCTAssertEqual(total, 1.0, accuracy: 1e-9)
    }

    func testExpectedWeights() {
        XCTAssertEqual(FitScorer.dimensionWeights["required_qualifications"], 0.45)
        XCTAssertEqual(FitScorer.dimensionWeights["preferred_qualifications"], 0.05)
        XCTAssertEqual(FitScorer.dimensionWeights["skills"], 0.15)
        XCTAssertEqual(FitScorer.dimensionWeights["experience_level"], 0.20)
        XCTAssertEqual(FitScorer.dimensionWeights["domain_fit"], 0.15)
    }

    // MARK: - Weighted score (no penalty)

    func testPerfectScore() {
        let result = FitScorer.computeScore(dimensions: allDimensions(100))
        XCTAssertEqual(result.overall, 100)
        XCTAssertEqual(result.penalty, 0)
    }

    func testZeroScore() {
        let result = FitScorer.computeScore(dimensions: allDimensions(0))
        XCTAssertEqual(result.overall, 0)
    }

    func testMidpointScore() {
        // All dimensions = 50 → weighted sum = 50 * (0.45+0.05+0.15+0.20+0.15) = 50
        let result = FitScorer.computeScore(dimensions: allDimensions(50))
        XCTAssertEqual(result.overall, 50)
    }

    func testHeterogeneousWeightedScore() {
        // required=80, preferred=60, skills=70, experience=90, domain=50
        // weighted = 80*0.45 + 60*0.05 + 70*0.15 + 90*0.20 + 50*0.15
        //          = 36 + 3 + 10.5 + 18 + 7.5 = 75 / 1.0 = 75
        let dims: [String: Double] = [
            "required_qualifications": 80,
            "preferred_qualifications": 60,
            "skills": 70,
            "experience_level": 90,
            "domain_fit": 50
        ]
        let result = FitScorer.computeScore(dimensions: dims)
        XCTAssertEqual(result.overall, 75)
        XCTAssertEqual(result.penalty, 0)
    }

    func testPartialDimensionsNormalized() {
        // Only required_qualifications supplied with score 100; missing dimensions score 0.
        // weightedSum = 100 * 0.45 = 45, totalWeight = 1.0 (all expected dims)
        // baseScore = round(45 / 1.0) = 45
        let result = FitScorer.computeScore(dimensions: ["required_qualifications": 100])
        XCTAssertEqual(result.overall, 45)
    }

    // MARK: - Penalty model

    func testGenericMissingRequirementCosts5() {
        let result = FitScorer.computeScore(
            dimensions: allDimensions(100),
            requirementsNotMet: ["5 years Python experience"]
        )
        XCTAssertEqual(result.penalty, 5)
        XCTAssertEqual(result.overall, 95)
    }

    func testDomainGapKeywordCosts10() {
        // ASIC → domain gap keyword
        let result = FitScorer.computeScore(
            dimensions: allDimensions(100),
            requirementsNotMet: ["ASIC design experience required"]
        )
        XCTAssertEqual(result.penalty, 10)
        XCTAssertEqual(result.overall, 90)
    }

    func testAllDomainGapKeywordsRecognized() {
        let keywords = [
            "asic",
            "fpga",
            "rtl",
            "tapeout",
            "tape-out",
            "silicon",
            "emulation",
            "hyperscaler",
            "cloud service",
            "soc ",
            "vlsi",
            "gds"
        ]
        for keyword in keywords {
            let result = FitScorer.computeScore(
                dimensions: allDimensions(100),
                requirementsNotMet: ["needs \(keyword) expertise"]
            )
            XCTAssertEqual(result.penalty, 10, "keyword '\(keyword)' should cost 10")
        }
    }

    func testPenaltyCappedAt50() {
        // 11 generic items × 5 = 55 → capped at 50
        let notMet = (0 ..< 11).map { "requirement \($0)" }
        let result = FitScorer.computeScore(
            dimensions: allDimensions(100),
            requirementsNotMet: notMet
        )
        XCTAssertEqual(result.penalty, 50)
    }

    func testPenaltyCappedAt50WithDomainGaps() {
        // 6 domain-gap items × 10 = 60 → capped at 50
        let notMet = (0 ..< 6).map { "requires fpga \($0)" }
        let result = FitScorer.computeScore(
            dimensions: allDimensions(100),
            requirementsNotMet: notMet
        )
        XCTAssertEqual(result.penalty, 50)
    }

    func testOverallFlooredAtZero() {
        // base = 10, penalty capped at 50 → 10 - 50 = -40 → floored to 0
        let notMet = (0 ..< 11).map { "requirement \($0)" }
        let result = FitScorer.computeScore(
            dimensions: allDimensions(10),
            requirementsNotMet: notMet
        )
        XCTAssertEqual(result.overall, 0)
        XCTAssertGreaterThanOrEqual(result.overall, 0)
    }

    // MARK: - penaltyReasons

    func testPenaltyReasonsListedCorrectly() {
        let notMet = ["No ML experience", "No FPGA skills"]
        let result = FitScorer.computeScore(
            dimensions: allDimensions(80),
            requirementsNotMet: notMet
        )
        XCTAssertEqual(result.penaltyReasons.count, 2)
        XCTAssertTrue(result.penaltyReasons.contains("No ML experience"))
        XCTAssertTrue(result.penaltyReasons.contains("No FPGA skills"))
    }

    // MARK: - Breakdown dictionary

    func testBreakdownContainsAllDimensions() {
        let dims = allDimensions(75)
        let result = FitScorer.computeScore(dimensions: dims)
        for key in FitScorer.dimensionWeights.keys {
            XCTAssertNotNil(result.breakdown[key], "breakdown missing key: \(key)")
        }
    }

    func testBreakdownClampsScoreTo100() {
        let result = FitScorer.computeScore(dimensions: allDimensions(150))
        for (_, score) in result.breakdown {
            XCTAssertLessThanOrEqual(score, 100)
        }
    }

    func testBreakdownClampsScoreToZero() {
        let result = FitScorer.computeScore(dimensions: allDimensions(-10))
        for (_, score) in result.breakdown {
            XCTAssertGreaterThanOrEqual(score, 0)
        }
    }

    // MARK: - scoreWeights in result

    func testResultContainsScoreWeights() {
        let result = FitScorer.computeScore(dimensions: allDimensions(80))
        XCTAssertEqual(result.scoreWeights["required_qualifications"], 0.45)
        XCTAssertEqual(result.scoreWeights.count, FitScorer.dimensionWeights.count)
    }

    // MARK: - rescoreFromJSON

    func testRescoreFromJSONSwiftFormat() throws {
        let original = FitScorer.computeScore(
            dimensions: allDimensions(80),
            requirementsNotMet: ["Python", "FPGA experience"]
        )
        let json = try XCTUnwrap(FitScorer.encode(original))
        let rescored = try XCTUnwrap(FitScorer.rescoreFromJSON(json))
        XCTAssertEqual(rescored.overall, original.overall)
        XCTAssertEqual(rescored.penalty, original.penalty)
    }

    func testRescoreFromJSONLegacyArrayFormat() throws {
        // Simulate the JS-produced format stored in the database.
        let legacyJSON = """
        {
            "overall_score": 70,
            "requirements_penalty": 5,
            "requirements_met": ["Python"],
            "requirements_not_met": ["5+ years managing teams"],
            "summary": "Good fit overall",
            "score_weights": {
                "required_qualifications": 0.45,
                "preferred_qualifications": 0.05,
                "skills": 0.15,
                "experience_level": 0.20,
                "domain_fit": 0.15
            },
            "dimensions": [
                {"name": "required_qualifications", "score": 80, "rationale": "Meets most requirements"},
                {"name": "preferred_qualifications", "score": 60, "rationale": "Some preferred"},
                {"name": "skills", "score": 75, "rationale": "Good skills"},
                {"name": "experience_level", "score": 70, "rationale": "Appropriate level"},
                {"name": "domain_fit", "score": 65, "rationale": "Related domain"}
            ]
        }
        """
        // Manually compute expected:
        // weighted = 80*0.45 + 60*0.05 + 75*0.15 + 70*0.20 + 65*0.15
        //          = 36 + 3 + 11.25 + 14 + 9.75 = 74 (rounds to 74)
        // penalty from "5+ years managing teams" → generic → 5
        // overall = max(0, 74 - 5) = 69
        let result = try XCTUnwrap(FitScorer.rescoreFromJSON(legacyJSON))
        XCTAssertEqual(result.penalty, 5)
        XCTAssertEqual(result.overall, 69)
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
            requirementsNotMet: ["RTL design", "Java"]
        )
        let json = try XCTUnwrap(FitScorer.encode(result))
        let decoded = try XCTUnwrap(FitScorer.decode(from: json))
        XCTAssertEqual(decoded.overall, result.overall)
        XCTAssertEqual(decoded.penalty, result.penalty)
        XCTAssertEqual(decoded.penaltyReasons, result.penaltyReasons)
        XCTAssertEqual(decoded.breakdown.count, result.breakdown.count)
    }

    // MARK: - TASK-254: Missing dimensions are treated as 0, not excluded from normalization

    func testAllDimensionsPresent_sameResultAsExpected() {
        // With all dims present, result is identical to the heterogeneous test above.
        let dims: [String: Double] = [
            "required_qualifications": 80,
            "preferred_qualifications": 60,
            "skills": 70,
            "experience_level": 90,
            "domain_fit": 50
        ]
        let result = FitScorer.computeScore(dimensions: dims)
        // weighted = 80*0.45 + 60*0.05 + 70*0.15 + 90*0.20 + 50*0.15 = 75
        XCTAssertEqual(result.overall, 75)
    }

    func testMissingOneDimension_lowerScoreThanIfPresent() {
        // With all dims at 100, overall == 100.
        let full = FitScorer.computeScore(dimensions: allDimensions(100))
        XCTAssertEqual(full.overall, 100)

        // Drop domain_fit (weight 0.15). Missing dims score 0, so:
        // weightedSum = 100*(0.45+0.05+0.15+0.20) = 100*0.85 = 85
        // totalWeight = 1.0 → baseScore = 85
        var partial = FitScorer.dimensionWeights.keys.reduce(into: [String: Double]()) { d, k in
            d[k] = 100
        }
        partial.removeValue(forKey: "domain_fit")
        let result = FitScorer.computeScore(dimensions: partial)
        XCTAssertEqual(result.overall, 85)
        XCTAssertLessThan(
            result.overall,
            full.overall,
            "A partial response must score lower than a full response with the same values"
        )
    }

    func testAllDimensionsMissing_scoreIsZero() {
        let result = FitScorer.computeScore(dimensions: [:])
        XCTAssertEqual(result.overall, 0)
    }

    // MARK: - Empty dimensions

    func testEmptyDimensionsReturnsZero() {
        let result = FitScorer.computeScore(dimensions: [:])
        XCTAssertEqual(result.overall, 0)
        XCTAssertEqual(result.penalty, 0)
    }

    // MARK: - No missing requirements

    func testNoPenaltyWhenNoRequirementsNotMet() {
        let result = FitScorer.computeScore(
            dimensions: allDimensions(80),
            requirementsNotMet: []
        )
        XCTAssertEqual(result.penalty, 0)
        XCTAssertEqual(result.overall, 80)
    }

    // MARK: - Case insensitivity of domain gap keywords

    func testDomainGapKeywordCaseInsensitive() {
        let result = FitScorer.computeScore(
            dimensions: allDimensions(100),
            requirementsNotMet: ["FPGA Design", "RTL Coding Required"]
        )
        // Both FPGA and RTL are domain gap keywords → 10 + 10 = 20
        XCTAssertEqual(result.penalty, 20)
        XCTAssertEqual(result.overall, 80)
    }

    // MARK: - Mixed generic and domain-gap

    func testMixedPenalty() {
        // 2 generic × 5 = 10, 1 domain (hyperscaler) × 10 = 10 → total 20
        let notMet = ["Python required", "Go experience", "hyperscaler background needed"]
        let result = FitScorer.computeScore(
            dimensions: allDimensions(100),
            requirementsNotMet: notMet
        )
        XCTAssertEqual(result.penalty, 20)
        XCTAssertEqual(result.overall, 80)
    }

    // MARK: - TASK-453: dimension contract validation

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
