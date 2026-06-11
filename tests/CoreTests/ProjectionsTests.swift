import XCTest
@testable import JobhuntCore

final class ProjectionsTests: XCTestCase {

    // MARK: - JobDetailProjection: extracted JSON parsing

    func testProjection_populatedJSON() throws {
        let json = """
        {
            "summary": "Great role",
            "requirements": ["Swift", "SwiftUI"],
            "nice_to_have": ["Combine"],
            "skills": ["iOS"]
        }
        """
        let job = Job(id: "j1", jobNumber: 1, company: "Acme", title: "iOS Dev",
                      manualOverridesJSON: "[]", extractedJSON: json)
        let p = JobDetailProjection(job: job)
        XCTAssertEqual(p.summary, "Great role")
        XCTAssertEqual(p.requirements, ["Swift", "SwiftUI"])
        XCTAssertEqual(p.niceToHaves, ["Combine"])
        XCTAssertEqual(p.skills, ["iOS"])
    }

    func testProjection_niceToHavesAlternateKey() {
        let json = "{\"nice_to_haves\": [\"Docker\"]}"
        let job = Job(id: "j2", jobNumber: 2, company: "X", title: "T",
                      manualOverridesJSON: "[]", extractedJSON: json)
        let p = JobDetailProjection(job: job)
        XCTAssertEqual(p.niceToHaves, ["Docker"])
    }

    func testProjection_missingJSON_returnsEmptyDefaults() {
        let job = Job(id: "j3", jobNumber: 3, company: "X", title: "T",
                      manualOverridesJSON: "[]", extractedJSON: nil)
        let p = JobDetailProjection(job: job)
        XCTAssertNil(p.summary)
        XCTAssertTrue(p.requirements.isEmpty)
        XCTAssertTrue(p.niceToHaves.isEmpty)
        XCTAssertTrue(p.skills.isEmpty)
    }

    func testProjection_malformedJSON_returnsEmptyDefaults() {
        let job = Job(id: "j4", jobNumber: 4, company: "X", title: "T",
                      manualOverridesJSON: "[]", extractedJSON: "not json at all")
        let p = JobDetailProjection(job: job)
        XCTAssertNil(p.summary)
        XCTAssertTrue(p.requirements.isEmpty)
    }

    func testProjection_manualOverrides_takePrecedenceOverExtractedSkills() {
        let json = "{\"skills\": [\"Swift\"]}"
        let job = Job(id: "j5", jobNumber: 5, company: "X", title: "T",
                      manualOverridesJSON: "[\"Kotlin\"]", extractedJSON: json)
        let p = JobDetailProjection(job: job)
        XCTAssertEqual(p.skills, ["Kotlin"])
    }

    func testProjection_malformedManualOverrides_fallsBackToExtracted() {
        let json = "{\"skills\": [\"Swift\"]}"
        let job = Job(id: "j6", jobNumber: 6, company: "X", title: "T",
                      manualOverridesJSON: "not-json", extractedJSON: json)
        let p = JobDetailProjection(job: job)
        XCTAssertEqual(p.skills, ["Swift"])
    }

    // MARK: - FitScoreProjection

    func testFitProjection_populatedJSON() {
        let json = """
        {
            "requirements_met": ["Swift", "SwiftUI"],
            "requirements_not_met": ["C++"],
            "dimensions": [
                {"name": "skills", "score": 80, "rationale": "Good match"},
                {"name": "experience_level", "score": 70}
            ]
        }
        """
        let fitScore = JobFitScore(fitScore: 80, fitStatus: .succeeded, fitScoreJSON: json)
        let p = FitScoreProjection(fitScore: fitScore)
        XCTAssertEqual(p.requirementsMet, ["Swift", "SwiftUI"])
        XCTAssertEqual(p.requirementsNotMet, ["C++"])
        XCTAssertEqual(p.dimensions.count, 2)
        XCTAssertEqual(p.dimensions[0].name, "skills")
        XCTAssertEqual(p.dimensions[0].score, 80)
        XCTAssertEqual(p.dimensions[0].rationale, "Good match")
        XCTAssertEqual(p.dimensions[1].name, "experience_level")
        XCTAssertNil(p.dimensions[1].rationale)
    }

    func testFitProjection_nilJSON_returnsEmptyDefaults() {
        let fitScore = JobFitScore(fitScore: nil, fitStatus: .none, fitScoreJSON: nil)
        let p = FitScoreProjection(fitScore: fitScore)
        XCTAssertTrue(p.requirementsMet.isEmpty)
        XCTAssertTrue(p.requirementsNotMet.isEmpty)
        XCTAssertTrue(p.dimensions.isEmpty)
    }

    func testFitProjection_malformedJSON_returnsEmptyDefaults() {
        let fitScore = JobFitScore(fitScore: 50, fitStatus: .failed, fitScoreJSON: "{bad}")
        let p = FitScoreProjection(fitScore: fitScore)
        XCTAssertTrue(p.requirementsMet.isEmpty)
        XCTAssertTrue(p.dimensions.isEmpty)
    }

    func testFitProjection_dimensionsMissingRequiredFields_skipped() {
        let json = """
        {"dimensions": [{"score": 90}, {"name": "skills"}]}
        """
        let fitScore = JobFitScore(fitScore: 90, fitStatus: .succeeded, fitScoreJSON: json)
        let p = FitScoreProjection(fitScore: fitScore)
        XCTAssertTrue(p.dimensions.isEmpty)
    }

    // MARK: - SalaryDisplay

    func testSalaryDisplay_bothMinMax_USD() {
        XCTAssertEqual(SalaryDisplay.text(min: 120000, max: 160000, currency: "USD"), "$120k–$160k")
    }

    func testSalaryDisplay_minOnly() {
        XCTAssertEqual(SalaryDisplay.text(min: 100000, max: nil, currency: nil), "$100k+")
    }

    func testSalaryDisplay_maxOnly() {
        XCTAssertEqual(SalaryDisplay.text(min: nil, max: 80000, currency: "USD"), "up to $80k")
    }

    func testSalaryDisplay_GBP() {
        XCTAssertEqual(SalaryDisplay.text(min: 50000, max: 70000, currency: "GBP"), "£50k–£70k")
    }

    func testSalaryDisplay_EUR() {
        XCTAssertEqual(SalaryDisplay.text(min: 60000, max: nil, currency: "EUR"), "€60k+")
    }

    func testSalaryDisplay_neitherMinNorMax_returnsNil() {
        XCTAssertNil(SalaryDisplay.text(min: nil, max: nil, currency: "USD"))
    }

    func testSalaryDisplay_subThousandAmount() {
        XCTAssertEqual(SalaryDisplay.text(min: 500, max: nil, currency: nil), "$500+")
    }
}
