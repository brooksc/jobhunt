import XCTest
@testable import JobhuntCore

final class ProjectionsTests: XCTestCase {
    // MARK: - JobDetailProjection: extracted JSON parsing

    func testProjection_populatedJSON() {
        let json = """
        {
            "summary": "Great role",
            "requirements": ["Swift", "SwiftUI"],
            "nice_to_have": ["Combine"],
            "skills": ["iOS"]
        }
        """
        let job = Job(
            id: "j1",
            jobNumber: 1,
            company: "Acme",
            title: "iOS Dev",
            manualOverridesJSON: "[]",
            extractedJSON: json
        )
        let p = JobDetailProjection(job: job)
        XCTAssertEqual(p.summary, "Great role")
        XCTAssertEqual(p.requirements, ["Swift", "SwiftUI"])
        XCTAssertEqual(p.niceToHaves, ["Combine"])
        XCTAssertEqual(p.skills, ["iOS"])
    }

    func testProjection_niceToHavesAlternateKey() {
        let json = "{\"nice_to_haves\": [\"Docker\"]}"
        let job = Job(
            id: "j2",
            jobNumber: 2,
            company: "X",
            title: "T",
            manualOverridesJSON: "[]",
            extractedJSON: json
        )
        let p = JobDetailProjection(job: job)
        XCTAssertEqual(p.niceToHaves, ["Docker"])
    }

    func testProjection_missingJSON_returnsEmptyDefaults() {
        let job = Job(
            id: "j3",
            jobNumber: 3,
            company: "X",
            title: "T",
            manualOverridesJSON: "[]",
            extractedJSON: nil
        )
        let p = JobDetailProjection(job: job)
        XCTAssertNil(p.summary)
        XCTAssertTrue(p.requirements.isEmpty)
        XCTAssertTrue(p.niceToHaves.isEmpty)
        XCTAssertTrue(p.skills.isEmpty)
    }

    func testProjection_malformedJSON_returnsEmptyDefaults() {
        let job = Job(
            id: "j4",
            jobNumber: 4,
            company: "X",
            title: "T",
            manualOverridesJSON: "[]",
            extractedJSON: "not json at all"
        )
        let p = JobDetailProjection(job: job)
        XCTAssertNil(p.summary)
        XCTAssertTrue(p.requirements.isEmpty)
    }

    func testProjection_manualOverrides_takePrecedenceOverExtractedSkills() {
        let json = "{\"skills\": [\"Swift\"]}"
        let job = Job(
            id: "j5",
            jobNumber: 5,
            company: "X",
            title: "T",
            manualOverridesJSON: "[\"Kotlin\"]",
            extractedJSON: json
        )
        let p = JobDetailProjection(job: job)
        XCTAssertEqual(p.skills, ["Kotlin"])
    }

    func testProjection_malformedManualOverrides_fallsBackToExtracted() {
        let json = "{\"skills\": [\"Swift\"]}"
        let job = Job(
            id: "j6",
            jobNumber: 6,
            company: "X",
            title: "T",
            manualOverridesJSON: "not-json",
            extractedJSON: json
        )
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
        XCTAssertTrue(p.requirementAssessments.isEmpty)
    }

    // TASK-490: structured per-requirement assessments parse, and met/not-met are derived from them
    // (met → met; partial + missing → not met).
    func testFitProjection_requirementAssessments() {
        let json = """
        {
            "requirement_assessments": [
                {"requirement": "5+ years iOS", "status": "met", "evidence": "6 years."},
                {"requirement": "Strong SwiftUI knowledge", "status": "partial", "evidence": "Some exposure."},
                {"requirement": "Experience with Kotlin", "status": "missing", "evidence": "Absent."}
            ],
            "dimensions": [{"name": "skills", "score": 80}]
        }
        """
        let p = FitScoreProjection(fitScore: JobFitScore(fitScore: 72, fitStatus: .succeeded, fitScoreJSON: json))
        XCTAssertEqual(p.requirementAssessments.count, 3)
        XCTAssertEqual(p.requirementAssessments[0].status, "met")
        XCTAssertTrue(p.requirementAssessments[0].isMet)
        XCTAssertEqual(p.requirementAssessments[1].evidence, "Some exposure.")
        // Derived splits: met vs (partial + missing)
        XCTAssertEqual(p.requirementsMet, ["5+ years iOS"])
        XCTAssertEqual(Set(p.requirementsNotMet), ["Strong SwiftUI knowledge", "Experience with Kotlin"])
    }

    func testFitProjection_requirementAssessments_parsesKind() {
        let json = """
        {
            "requirement_assessments": [
                {"requirement": "5+ years iOS", "kind": "required", "status": "met", "evidence": "6 years."},
                {"requirement": "Experience with Kotlin", "kind": "preferred", "status": "missing", "evidence": "Absent."},
                {"requirement": "Experience with legacy systems", "status": "partial", "evidence": "No kind field."}
            ]
        }
        """
        let p = FitScoreProjection(fitScore: JobFitScore(fitScore: 60, fitStatus: .succeeded, fitScoreJSON: json))
        XCTAssertEqual(p.requirementAssessments[0].kind, "required")
        XCTAssertFalse(p.requirementAssessments[0].isPreferred)
        XCTAssertEqual(p.requirementAssessments[1].kind, "preferred")
        XCTAssertTrue(p.requirementAssessments[1].isPreferred)
        XCTAssertEqual(p.requirementAssessments[2].kind, "unknown", "missing kind defaults to unknown (legacy)")
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

    func testFitScoreProjection_integerDimensionScores() {
        let json = """
        {
            "dimensions": [
                {"name": "skills", "score": 85},
                {"name": "experience_level", "score": 70}
            ]
        }
        """
        let fitScore = JobFitScore(fitScore: 85, fitStatus: .succeeded, fitScoreJSON: json)
        let p = FitScoreProjection(fitScore: fitScore)
        XCTAssertEqual(p.dimensions.count, 2)
        XCTAssertEqual(p.dimensions[0].score, 85)
        XCTAssertEqual(p.dimensions[1].score, 70)
    }

    func testFitScoreProjection_floatingPointDimensionScores() {
        let json = """
        {
            "dimensions": [
                {"name": "skills", "score": 85.5},
                {"name": "experience_level", "score": 70.2},
                {"name": "culture_fit", "score": 94.9}
            ]
        }
        """
        let fitScore = JobFitScore(fitScore: 85, fitStatus: .succeeded, fitScoreJSON: json)
        let p = FitScoreProjection(fitScore: fitScore)
        XCTAssertEqual(p.dimensions.count, 3)
        XCTAssertEqual(p.dimensions[0].score, 86, "85.5 should round to 86")
        XCTAssertEqual(p.dimensions[1].score, 70, "70.2 should round to 70")
        XCTAssertEqual(p.dimensions[2].score, 95, "94.9 should round to 95")
    }

    // MARK: - SalaryDisplay

    func testSalaryDisplay_bothMinMax_USD() {
        XCTAssertEqual(SalaryDisplay.text(min: 120_000, max: 160_000, currency: "USD"), "$120k–$160k")
    }

    func testSalaryDisplay_minOnly() {
        XCTAssertEqual(SalaryDisplay.text(min: 100_000, max: nil, currency: nil), "$100k+")
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

    // MARK: - TASK-464: MCP payload fields re-added to JobDetailRecord/JobListRecord

    func testJobRecords_exposeEmploymentSeniorityAndDuplicate() {
        let job = Job(
            jobNumber: 1,
            title: "Eng",
            employmentType: "full_time",
            seniority: "staff",
            duplicateOfJobID: "orig-1"
        )
        job.status = .duplicate

        let detail = JobDetailRecord(job: job)
        XCTAssertEqual(detail.employmentType, "full_time")
        XCTAssertEqual(detail.seniority, "staff")
        XCTAssertEqual(detail.duplicateOfJobID, "orig-1")

        let list = JobListRecord(job: job)
        XCTAssertEqual(list.employmentType, "full_time")
        XCTAssertEqual(list.seniority, "staff")
        XCTAssertEqual(list.duplicateOfJobID, "orig-1")
    }

    func testJobDetailRecord_includesEventsSortedByTime() {
        let job = Job(jobNumber: 1)
        let older = JobEvent(eventType: "status", note: "a")
        older.occurredAt = Date(timeIntervalSince1970: 100)
        let newer = JobEvent(eventType: "note", note: "b")
        newer.occurredAt = Date(timeIntervalSince1970: 200)
        job.events = [newer, older] // intentionally unsorted

        let detail = JobDetailRecord(job: job)
        XCTAssertEqual(detail.events.map(\.eventType), ["status", "note"], "events sorted by occurredAt")
        XCTAssertEqual(detail.events.first?.note, "a")
    }

    // MARK: - Trapping-conversion hardening (F9)

    func testFitProjection_hugeDimensionScore_doesNotTrap() {
        // An LLM-emitted out-of-range dimension score (parses as a Double but exceeds Int) used to trap
        // Int(_:) and abort the app (CWE-190). It must clamp to the 0–100 fit scale instead of crashing.
        let json = """
        {"dimensions": [{"name": "skills", "score": 1e19}, {"name": "seniority", "score": 250.5}]}
        """
        let p = FitScoreProjection(fitScore: JobFitScore(fitScore: 50, fitStatus: .succeeded, fitScoreJSON: json))
        XCTAssertEqual(p.dimensions.count, 2)
        XCTAssertEqual(p.dimensions.first(where: { $0.name == "skills" })?.score, 100, "1e19 clamps to 100")
        XCTAssertEqual(p.dimensions.first(where: { $0.name == "seniority" })?.score, 100, "250.5 clamps to 100")
    }
}

/// The number and the rows must move together. They didn't: rows came from the projection and
/// updated the moment a correction was saved, while the ring read the persisted score and waited for
/// the background recompute — so a requirement jumped from Gaps to Requirements met above a headline
/// that hadn't changed, which reads as the correction being ignored.
final class FitProjectionCorrectedScoreTests: XCTestCase {
    private let json = """
    {"overall": 60,
     "dimensions": [{"name":"required_qualifications","score":80},
                    {"name":"preferred_qualifications","score":60},
                    {"name":"skills","score":70},
                    {"name":"domain_fit","score":60},
                    {"name":"experience_level","score":90}],
     "requirement_assessments": [
       {"requirement":"Experience with distributed systems","kind":"required","status":"missing",
        "evidence":"Not evidenced — a reader of this resume would not credit it."},
       {"requirement":"8 years of program management","kind":"required","status":"met",
        "evidence":"Ten years leading programs."}
     ]}
    """

    private func projection(_ feedback: [ScoringFeedback]) -> FitScoreProjection {
        FitScoreProjection(
            fitScore: JobFitScore(fitScore: 60, fitStatus: .succeeded, fitScoreJSON: json),
            feedback: feedback,
            jobNumber: 1
        )
    }

    func testOverallScoreRespondsToACorrection() throws {
        let before = try XCTUnwrap(projection([]).overallScore)
        let after = try XCTUnwrap(
            projection([ScoringFeedback(phrase: "distributed systems", kind: .alwaysCredit)]).overallScore
        )
        XCTAssertGreaterThan(after, before, "crediting a missing requirement must raise the score")
    }

    /// The regression in the other direction: "I don't have this" must cost, not just recolour a row.
    func testMarkingSomethingMissingLowersTheScore() throws {
        let before = try XCTUnwrap(projection([]).overallScore)
        let after = try XCTUnwrap(
            projection([ScoringFeedback(phrase: "program management", kind: .neverCredit)]).overallScore
        )
        XCTAssertLessThan(after, before)
    }

    /// A corrected row must not keep evidence written for the verdict it no longer has — a green tick
    /// above "a reader of this resume would not credit it" is the app arguing with itself.
    func testCorrectedRowDropsTheContradictoryEvidence() throws {
        let p = projection([ScoringFeedback(phrase: "distributed systems", kind: .alwaysCredit)])
        let row = try XCTUnwrap(p.requirementAssessments.first { $0.requirement.contains("distributed") })
        XCTAssertEqual(row.status, "met")
        XCTAssertFalse(
            row.evidence.contains("would not credit"),
            "evidence still describes the model's original verdict: \(row.evidence)"
        )
        XCTAssertTrue(row.evidence.contains("You marked this"))
    }

    func testUncorrectedRowsKeepTheirEvidence() throws {
        let row = try XCTUnwrap(projection([]).requirementAssessments.first { $0.status == "met" })
        XCTAssertEqual(row.evidence, "Ten years leading programs.")
    }
}
