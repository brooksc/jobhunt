import SwiftData
import XCTest
@testable import JobhuntCore

/// Tests for BackgroundStore.pruneOrphanFitScores — removing legacy fit scores with no resume
/// linked (which otherwise render as a model name and hijack the job's "Best match").
final class PruneOrphanFitScoresTests: XCTestCase {
    func testPrune_deletesOrphansAndRecomputesJobMirror() async throws {
        let store = try BackgroundStore(modelContainer: ModelContainerFactory.inMemory())

        let resume = Resume(name: "Real Resume", text: "resume body")
        let job = Job(jobNumber: 136, title: "Staff TPM")
        // Orphan (no resume) with the highest score — this is what inflates the mirror.
        let orphan = JobFitScore(fitScore: 93, fitStatus: .succeeded, model: "gemma-4-e4b-it-mlx")
        orphan.job = job
        // Real resume-linked score, lower than the orphan.
        let real = JobFitScore(fitScore: 87, fitStatus: .succeeded, model: "lmstudio")
        real.job = job
        real.resume = resume
        job.fitScore = 93 // denormalized mirror currently reflects the orphan

        try await store.insert(resume)
        try await store.insert(job)
        try await store.insert(orphan)
        try await store.insert(real)

        let deleted = try await store.pruneOrphanFitScores()
        XCTAssertEqual(deleted, 1, "exactly the resume-less score is removed")

        let remaining = try await store.fetch(FetchDescriptor<JobFitScore>())
        XCTAssertEqual(remaining.count, 1)
        XCTAssertNotNil(remaining.first?.resume, "surviving score keeps its resume")

        let jobs = try await store.fetch(FetchDescriptor<Job>())
        XCTAssertEqual(jobs.first?.fitScore, 87, "mirror recomputed to the best resume-linked score")
        XCTAssertEqual(jobs.first?.fitStatus, .succeeded)
    }

    func testPrune_noOrphansIsNoOp() async throws {
        let store = try BackgroundStore(modelContainer: ModelContainerFactory.inMemory())
        let resume = Resume(name: "R", text: "body")
        let job = Job(jobNumber: 1, title: "SWE")
        let score = JobFitScore(fitScore: 80, fitStatus: .succeeded)
        score.job = job
        score.resume = resume
        try await store.insert(resume)
        try await store.insert(job)
        try await store.insert(score)

        let deleted = try await store.pruneOrphanFitScores()
        XCTAssertEqual(deleted, 0)
        let remaining = try await store.fetch(FetchDescriptor<JobFitScore>())
        XCTAssertEqual(remaining.count, 1)
    }

    func testPrune_clearsMirrorWhenAllScoresWereOrphans() async throws {
        let store = try BackgroundStore(modelContainer: ModelContainerFactory.inMemory())
        let job = Job(jobNumber: 7, title: "EM")
        let orphan = JobFitScore(fitScore: 90, fitStatus: .succeeded, model: "gemini-3.1-flash-lite")
        orphan.job = job
        job.fitScore = 90
        job.fitStatus = .succeeded
        try await store.insert(job)
        try await store.insert(orphan)

        let deleted = try await store.pruneOrphanFitScores()
        XCTAssertEqual(deleted, 1)

        let jobs = try await store.fetch(FetchDescriptor<Job>())
        XCTAssertNil(jobs.first?.fitScore, "mirror cleared when no resume-linked score remains")
        XCTAssertEqual(jobs.first?.fitStatus, FitStatus.none)
    }

    // TASK-472: a fit-failure message with control chars/quotes/backslashes must produce VALID
    // JSON. Hand-escaping only `"` left newlines/tabs raw → invalid JSON the UI silently dropped.
    func testMarkFitScoreFailed_errorWithControlCharsIsValidJSON() async throws {
        let store = try BackgroundStore(modelContainer: ModelContainerFactory.inMemory())
        let resume = Resume(name: "R", text: "body")
        let job = Job(jobNumber: 1, title: "SWE")
        try await store.insert(resume)
        try await store.insert(job)
        try await store.insertFitBatch(jobIDs: [job.id], resumeID: resume.id)

        let nasty = "HTTP 500: server said \"no\"\n\ttab + \\backslash"
        try await store.markFitScoreFailed(jobID: job.id, resumeID: resume.id, errorMessage: nasty)

        let scores = try await store.fetch(FetchDescriptor<JobFitScore>())
        let json = try XCTUnwrap(scores.first(where: { $0.fitStatus == .failed })?.fitScoreJSON)
        let parsed = try JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any]
        XCTAssertEqual(parsed?["error"] as? String, nasty, "error must round-trip as valid JSON")
    }
}
