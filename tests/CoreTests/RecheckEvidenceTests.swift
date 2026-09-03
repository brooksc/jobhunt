import SwiftData
import XCTest
@testable import JobhuntCore

/// TASK-706: both evidence-check callers used to pass the *one* résumé linked to the score, though
/// `EvidenceCheck.classify` documents that it must be given every résumé the user has ever had
/// active. A quote lifted accurately out of a different (or superseded) résumé was therefore reported
/// to the user as invented — a false accusation in a verdict that drives "I don't have this" and
/// feeds the scoring-feedback loop.
final class RecheckEvidenceTests: XCTestCase {
    private let quoted = "Rebuilt the settlement pipeline at Northwind"

    private func analysis() -> String {
        """
        {"overall":74,"requirement_assessments":[{"requirement":"Payments experience",
         "kind":"required","status":"met","evidence":"Résumé says '\(quoted)'."}]}
        """
    }

    private func currentResume() -> Resume {
        Resume(name: "Current", text: "Swift developer, 5 years.")
    }

    private func supersededResume() -> Resume {
        Resume(name: "Older", text: "\(quoted). Cut release lead time from 40 to 3 days.", active: false)
    }

    private func addScoredJob(_ store: BackgroundStore, number: Int, resume: Resume?) async throws {
        let job = Job(jobNumber: number, title: "Payments Engineer \(number)")
        job.capture = Capture(
            url: "https://example.com/job/\(number)", pageTitle: "Payments Engineer",
            cleanedDescription: "You will apply sound business judgment to payment systems.",
            rawHash: "h\(number)"
        )
        let record = JobFitScore(
            fitScore: 74, fitStatus: .succeeded, fitScoreJSON: analysis(), model: "m", scoredAt: Date()
        )
        record.job = job
        record.resume = resume
        try await store.insert(job)
        try await store.insert(record)
    }

    /// `resumes.first` is the one the score was run against.
    private func seed(_ resumes: [Resume], jobs: Int = 1) async throws -> BackgroundStore {
        let store = try BackgroundStore(modelContainer: ModelContainerFactory.inMemory())
        for resume in resumes {
            try await store.insert(resume)
        }
        for number in 1 ... jobs {
            try await addScoredJob(store, number: number, resume: resumes.first)
        }
        return store
    }

    private func supportMarks(_ store: BackgroundStore) async throws -> [String] {
        let json = try await store.fetch(FetchDescriptor<JobFitScore>()).compactMap(\.fitScoreJSON)
        return json.compactMap { text -> String? in
            guard let data = text.data(using: .utf8),
                  let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let assessments = dict["requirement_assessments"] as? [[String: Any]]
            else { return nil }
            return assessments.first?[EvidenceCheck.supportKey] as? String
        }
    }

    func testAQuoteFromASupersededResumeIsNotFlagged() async throws {
        let store = try await seed([currentResume(), supersededResume()])
        let result = try await store.recheckStoredEvidence()
        XCTAssertEqual(result.checked, 1)
        XCTAssertEqual(
            result.flagged, 0, "A verbatim quote from another of the user's résumés is not invented"
        )
        let marks = try await supportMarks(store)
        XCTAssertEqual(marks, [])
    }

    /// The same span with only the scored résumé in the store — proves the test above isn't passing
    /// because nothing was checked.
    func testTheSameQuoteIsFlaggedWhenNoResumeContainsIt() async throws {
        let store = try await seed([currentResume()])
        let result = try await store.recheckStoredEvidence()
        XCTAssertEqual(result.checked, 1)
        XCTAssertEqual(result.flagged, 1)
        let marks = try await supportMarks(store)
        XCTAssertEqual(marks, [EvidenceCheck.Support.invented.rawValue])
    }

    /// The set is gathered once for the whole run rather than per record, so every row in the pass is
    /// judged against the same résumés — five scored jobs, one fetch, none of them flagged.
    func testTheResumeSetAppliesToEveryRecordInOneRun() async throws {
        let store = try await seed([currentResume(), supersededResume()], jobs: 5)
        let result = try await store.recheckStoredEvidence()
        XCTAssertEqual(result.checked, 5)
        XCTAssertEqual(result.flagged, 0)
        let marks = try await supportMarks(store)
        XCTAssertEqual(marks, [])
    }

    /// The live scoring path gets the same set through `FitInputs`, built on the store actor rather
    /// than by the engine reaching into the store.
    func testFitInputsCarriesTheUsersOtherResumes() async throws {
        let current = currentResume()
        let older = supersededResume()
        let store = try await seed([current, older])
        let jobs = try await store.fetch(FetchDescriptor<Job>())
        let jobID = try XCTUnwrap(jobs.first?.id)
        let inputs = try await store.fitInputs(forJobID: jobID, resumeID: current.id)
        XCTAssertEqual(inputs?.resumeText, current.text)
        XCTAssertEqual(inputs?.otherResumeTexts, [older.text])
    }
}
