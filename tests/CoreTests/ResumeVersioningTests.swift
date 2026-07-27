import Foundation
import SwiftData
import XCTest
@testable import JobhuntCore

/// Editing a résumé used to DELETE every fit score computed against it — hundreds of paid LLM calls
/// destroyed by a one-line tweak, with no way back. Scores are now versioned and kept.
final class ResumeVersioningTests: XCTestCase {
    private func makeStore() throws -> BackgroundStore {
        try BackgroundStore(modelContainer: ModelContainerFactory.inMemory())
    }

    // MARK: - Fingerprint

    func testIdenticalTextHashesEqual() {
        XCTAssertEqual(ResumeFingerprint.hash("Staff TPM, 10 years"), ResumeFingerprint.hash("Staff TPM, 10 years"))
    }

    func testDifferentTextHashesDiffer() {
        XCTAssertNotEqual(ResumeFingerprint.hash("Staff TPM"), ResumeFingerprint.hash("Senior TPM"))
    }

    /// A reflow or trailing newline isn't a substantive edit and must not invalidate paid work.
    func testWhitespaceOnlyChangesDoNotCountAsAnEdit() {
        let a = "Led platform teams.\nShipped 4 products."
        let b = "  Led platform   teams.\n\n Shipped 4 products.  \n"
        XCTAssertEqual(ResumeFingerprint.hash(a), ResumeFingerprint.hash(b))
    }

    // MARK: - Staleness

    func testScoreIsNotStaleWhenResumeIsUnchanged() {
        let resume = Resume(name: "Master", text: "Staff TPM, 10 years")
        let score = JobFitScore()
        score.resume = resume
        score.resumeTextHash = ResumeFingerprint.hash(resume.text)
        XCTAssertFalse(score.reflectsPreviousResumeVersion)
    }

    func testScoreIsStaleAfterTheResumeIsEdited() {
        let resume = Resume(name: "Master", text: "Staff TPM, 10 years")
        let score = JobFitScore()
        score.resume = resume
        score.resumeTextHash = ResumeFingerprint.hash(resume.text)
        resume.text = "Staff TPM, 10 years. Added Kubernetes."
        XCTAssertTrue(score.reflectsPreviousResumeVersion)
    }

    /// Rows written before version tracking have no hash. They're *unknown*, not stale — labelling
    /// every historic score "previous version" would be a lie.
    func testLegacyScoresWithoutAHashAreNotReportedStale() {
        let resume = Resume(name: "Master", text: "Staff TPM")
        let score = JobFitScore()
        score.resume = resume
        score.resumeTextHash = nil
        XCTAssertFalse(score.reflectsPreviousResumeVersion)
    }

    // MARK: - Editing keeps the scores

    /// The regression that motivated all of this.
    func testEditingAResumeNoLongerDeletesItsScores() async throws {
        let store = try makeStore()
        try await store.insert(Resume(name: "Master", text: "Staff TPM, 10 years", active: true))
        try await store.insert(Job(id: "job-1", company: "Acme", title: "TPM", status: .pursuing))

        // Create the score through the real path so job/resume relationships are wired by the actor.
        let queued = try await store.enqueueFitForActiveResumes(jobID: "job-1")
        XCTAssertEqual(queued, 1)
        try await store.update(JobFitScore.self, predicate: nil) { record in
            record.fitScore = 88
            record.fitStatus = .succeeded
            record.resumeTextHash = record.resume.map { ResumeFingerprint.hash($0.text) }
        }

        let resumes = try await store.fetch(FetchDescriptor<Resume>())
        let service = ResumeService(store: store)
        let staleCount = try await service.updateResume(
            id: resumes[0].id, name: "Master", text: "Staff TPM, 10 years. Added Kubernetes."
        )

        let remaining = try await store.fetch(FetchDescriptor<JobFitScore>())
        XCTAssertEqual(remaining.count, 1, "the score must survive the edit")
        XCTAssertEqual(remaining.first?.fitScore, 88, "and keep its value")
        XCTAssertEqual(staleCount, 1, "the caller is told how many jobs a re-score would cover")
    }

    func testAnEditThatChangesNothingReportsNoStaleJobs() async throws {
        let store = try makeStore()
        let resume = Resume(name: "Master", text: "Staff TPM")
        try await store.insert(resume)
        let resumes = try await store.fetch(FetchDescriptor<Resume>())
        let service = ResumeService(store: store)
        let count = try await service.updateResume(id: resumes[0].id, name: "Master v2", text: "Staff TPM")
        XCTAssertEqual(count, 0, "a rename alone must not offer a re-score")
    }
}
