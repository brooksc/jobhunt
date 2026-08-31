import SwiftData
import XCTest
@testable import JobhuntCore

/// Tests for the queryable rubric-version column (TASK-711): the backfill that fills it from the
/// stored analysis, the histogram that reports it, and the selection of scores left on a superseded
/// rubric. A v1 68.9-mean population and a v3 50.0-mean population sat mixed in one store with no way
/// to tell them apart, which is what this column exists to fix.
final class FitScoreVersionTests: XCTestCase {
    private func analysis(version: Int?) -> String {
        let versionKey = version.map { "\"assessment_prompt_version\":\($0)," } ?? ""
        return "{\(versionKey)\"overall\":74,\"dimensions\":[]}"
    }

    /// A job with one succeeded score whose JSON carries `version`.
    private func seed(
        _ store: BackgroundStore,
        jobNumber: Int,
        version: Int?,
        score: Int = 74,
        resume: Resume?
    ) async throws {
        let job = Job(jobNumber: jobNumber, title: "Product Manager")
        let record = JobFitScore(
            fitScore: score,
            fitStatus: .succeeded,
            fitScoreJSON: analysis(version: version),
            model: "gemini-3.7-flash",
            scoredAt: Date()
        )
        record.job = job
        record.resume = resume
        try await store.insert(job)
        try await store.insert(record)
    }

    private func makeStore() async throws -> (BackgroundStore, Resume) {
        let store = try BackgroundStore(modelContainer: ModelContainerFactory.inMemory())
        let resume = Resume(name: "R", text: "Ten years of product work.")
        try await store.insert(resume)
        return (store, resume)
    }

    // MARK: - Backfill

    func testBackfillFillsVersionFromStoredJSON() async throws {
        let (store, resume) = try await makeStore()
        try await seed(store, jobNumber: 1, version: 1, resume: resume)
        try await seed(store, jobNumber: 2, version: 3, resume: resume)

        let result = try await store.backfillFitScorePromptVersions()
        XCTAssertEqual(result.updated, 2)
        XCTAssertEqual(result.unversioned, 0)

        let versions = try await store.fetch(FetchDescriptor<JobFitScore>())
            .compactMap(\.assessmentPromptVersion)
            .sorted()
        XCTAssertEqual(versions, [1, 3])
    }

    /// Re-running must be a no-op — the migrator modes are all safe to run twice.
    func testBackfillIsIdempotent() async throws {
        let (store, resume) = try await makeStore()
        try await seed(store, jobNumber: 1, version: 3, resume: resume)

        _ = try await store.backfillFitScorePromptVersions()
        let second = try await store.backfillFitScorePromptVersions()
        XCTAssertEqual(second.updated, 0)
    }

    /// An analysis with no version key leaves the column nil. Substituting 1 would make the handful of
    /// genuinely unversioned rows indistinguishable from the real v1 population.
    func testBackfillLeavesUnversionedRowsNil() async throws {
        let (store, resume) = try await makeStore()
        try await seed(store, jobNumber: 1, version: nil, resume: resume)

        let result = try await store.backfillFitScorePromptVersions()
        XCTAssertEqual(result.updated, 0)
        XCTAssertEqual(result.unversioned, 1)
        let rows = try await store.fetch(FetchDescriptor<JobFitScore>())
        let record = try XCTUnwrap(rows.first)
        XCTAssertNil(record.assessmentPromptVersion)
    }

    // MARK: - Histogram

    func testHistogramCountsAndMeansPerVersion() async throws {
        let (store, resume) = try await makeStore()
        try await seed(store, jobNumber: 1, version: 1, score: 80, resume: resume)
        try await seed(store, jobNumber: 2, version: 1, score: 60, resume: resume)
        try await seed(store, jobNumber: 3, version: 3, score: 50, resume: resume)
        try await seed(store, jobNumber: 4, version: nil, score: 40, resume: resume)
        _ = try await store.backfillFitScorePromptVersions()

        let rows = try await store.fitScorePromptVersionHistogram()
        XCTAssertEqual(rows.map(\.version), [1, 3, nil])
        XCTAssertEqual(rows.map(\.count), [2, 1, 1])
        XCTAssertEqual(rows[0].meanScore ?? 0, 70, accuracy: 0.001)
    }

    // MARK: - Stale selection

    func testStaleSelectionExcludesCurrentVersionAndResumeLessRows() async throws {
        let (store, resume) = try await makeStore()
        try await seed(store, jobNumber: 1, version: 1, resume: resume)
        try await seed(store, jobNumber: 2, version: 3, resume: resume)
        // No résumé: nothing to rescore against, so it must not enter the work set.
        try await seed(store, jobNumber: 3, version: 1, resume: nil)
        _ = try await store.backfillFitScorePromptVersions()

        let stale = try await store.staleFitScores(currentVersion: 3)
        XCTAssertEqual(stale.map(\.jobNumber), [1])
        XCTAssertEqual(stale.first?.version, 1)
    }

    /// A rescore commit stamps the current version, which is what takes the row out of the work set —
    /// the whole of the resumability mechanism.
    func testCommittingARescoreClearsItFromTheStaleSet() async throws {
        let (store, resume) = try await makeStore()
        try await seed(store, jobNumber: 1, version: 1, resume: resume)
        _ = try await store.backfillFitScorePromptVersions()

        let stale = try await store.staleFitScores(currentVersion: 3)
        let target = try XCTUnwrap(stale.first)
        let rescored = FitScoreOutput(
            score: FitScoreResult(
                overall: 74, breakdown: [:], penalty: 0, penaltyReasons: [], scoreWeights: [:]
            ),
            fitScoreJSON: analysis(version: 3),
            promptChars: 1, responseChars: 1,
            promptTokens: nil, completionTokens: nil,
            modelReturned: "gemini-3.7-flash", responseFormat: .jsonObject
        )
        try await store.commitRescoredFitScore(
            jobID: target.jobID, resumeID: target.resumeID, output: rescored
        )

        let remaining = try await store.staleFitScores(currentVersion: 3)
        XCTAssertTrue(remaining.isEmpty)
    }
}
