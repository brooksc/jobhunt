import SwiftData
import XCTest
@testable import JobhuntCore

/// Tests for BackgroundStore maintenance ops run out-of-band via JobhuntMigrator:
/// recomputeAllJobFitMirrors and pruneOrphanRequestAttempts.
final class StoreMaintenanceTests: XCTestCase {
    func testRecomputeFitMirrors_correctsDriftAndCountsOnlyChanged() async throws {
        let store = try BackgroundStore(modelContainer: ModelContainerFactory.inMemory())
        let resume = Resume(name: "R", text: "body")

        // Stale-high mirror: says 94 but best resume-linked score is 88.
        let stale = Job(jobNumber: 1, title: "Drifted")
        stale.fitScore = 94
        stale.fitStatus = .succeeded
        let s1 = JobFitScore(fitScore: 88, fitStatus: .succeeded)
        s1.job = stale; s1.resume = resume

        // Already consistent: mirror matches the score.
        let ok = Job(jobNumber: 2, title: "Consistent")
        ok.fitScore = 80
        ok.fitStatus = .succeeded
        let s2 = JobFitScore(fitScore: 80, fitStatus: .succeeded)
        s2.job = ok; s2.resume = resume

        try await store.insert(resume)
        for m in [stale, ok] {
            try await store.insert(m)
        }
        for m in [s1, s2] {
            try await store.insert(m)
        }

        let changed = try await store.recomputeAllJobFitMirrors()
        XCTAssertEqual(changed, 1, "only the drifted job is corrected")

        let jobs = try await store.fetch(FetchDescriptor<Job>())
        let byNum = Dictionary(uniqueKeysWithValues: jobs.map { ($0.jobNumber, $0) })
        XCTAssertEqual(byNum[1]?.fitScore, 88, "drift corrected to best resume-linked score")
        XCTAssertEqual(byNum[2]?.fitScore, 80, "consistent job unchanged")
    }

    func testPruneOrphanAttempts_deletesOnlyRequestlessAttempts() async throws {
        let store = try BackgroundStore(modelContainer: ModelContainerFactory.inMemory())

        // Linked attempt (has a parent request).
        let req = LLMRequest(requestType: .extract, status: .succeeded)
        req.finishedAt = Date()
        let linked = LLMRequestAttempt(
            requestType: .extract,
            attempt: 1,
            status: .succeeded,
            modelRequested: "lmstudio"
        )
        linked.request = req

        // Orphan attempt (no request).
        let orphan = LLMRequestAttempt(requestType: .fit, attempt: 1, status: .succeeded, modelRequested: "lmstudio")

        try await store.insert(req)
        try await store.insert(linked)
        try await store.insert(orphan)

        let deleted = try await store.pruneOrphanRequestAttempts()
        XCTAssertEqual(deleted, 1, "only the request-less attempt is deleted")

        let remaining = try await store.fetch(FetchDescriptor<LLMRequestAttempt>())
        XCTAssertEqual(remaining.count, 1)
        XCTAssertNotNil(remaining.first?.request, "surviving attempt keeps its request")
    }

    func testPruneOrphanAttempts_noOrphansIsNoOp() async throws {
        let store = try BackgroundStore(modelContainer: ModelContainerFactory.inMemory())
        let req = LLMRequest(requestType: .extract, status: .succeeded)
        let a = LLMRequestAttempt(requestType: .extract, attempt: 1, status: .succeeded, modelRequested: "x")
        a.request = req
        try await store.insert(req)
        try await store.insert(a)

        let deleted = try await store.pruneOrphanRequestAttempts()
        XCTAssertEqual(deleted, 0)
        let remaining = try await store.fetch(FetchDescriptor<LLMRequestAttempt>())
        XCTAssertEqual(remaining.count, 1)
    }

    // MARK: - mergeJob (--merge-job)

    /// The shape this exists for: a cosmetic URL difference forked a recapture into a second job, so
    /// the newer job holds the good extraction while the original holds the status and fit score.
    func testMergeJob_fillsMissingFieldsFromDuplicateAndDeletesIt() async throws {
        let store = try BackgroundStore(modelContainer: ModelContainerFactory.inMemory())
        let resume = Resume(name: "R", text: "body")

        // The keeper: stranded with a blank extraction, but carrying status and a settled fit score.
        let keeper = Job(jobNumber: 725)
        keeper.status = .applied
        keeper.extractionStatus = .pending
        keeper.fitScore = 84
        keeper.fitStatus = .succeeded
        let keeperScore = JobFitScore(fitScore: 84, fitStatus: .succeeded)
        keeperScore.job = keeper
        keeperScore.resume = resume

        // The fork: a clean extraction of the same posting.
        let fork = Job(jobNumber: 761, company: "Render", title: "Staff PM")
        fork.salaryMin = 218_000
        fork.salaryMax = 300_000
        fork.salaryCurrency = "USD"
        fork.extractionStatus = .succeeded
        fork.extractedJSON = "{}"
        fork.extractionModel = "anthropic/claude-haiku-4.5"
        fork.extractedAt = Date()

        try await store.insert(resume)
        try await store.insert(keeper)
        try await store.insert(fork)
        try await store.insert(keeperScore)

        let result = try await store.mergeJob(from: 761, into: 725)

        XCTAssertEqual(result.keptJobNumber, 725)
        XCTAssertEqual(result.removedJobNumber, 761)
        XCTAssertTrue(result.fieldsCopied.contains("company"))
        XCTAssertTrue(result.fieldsCopied.contains("salaryMin"))

        let jobs = try await store.fetch(FetchDescriptor<Job>())
        XCTAssertEqual(jobs.count, 1, "the duplicate is deleted")
        let merged = try XCTUnwrap(jobs.first)
        XCTAssertEqual(merged.jobNumber, 725)
        XCTAssertEqual(merged.company, "Render")
        XCTAssertEqual(merged.salaryMin, 218_000)
        XCTAssertEqual(merged.salaryMax, 300_000)
        XCTAssertEqual(merged.extractionStatus, .succeeded, "extraction provenance moves with the fields")
        XCTAssertEqual(merged.extractionModel, "anthropic/claude-haiku-4.5")
        XCTAssertEqual(merged.status, .applied, "the keeper's own status is untouched")
        XCTAssertEqual(merged.fitScore, 84, "the keeper's fit score survives the merge")

        let events = try await store.fetch(FetchDescriptor<JobEvent>())
        XCTAssertTrue(events.contains { $0.eventType == "merge" }, "the merge is recorded on the timeline")
    }

    /// Merging must never overwrite what the keeper already has — populated or manually edited.
    func testMergeJob_neverOverwritesExistingOrManuallyOverriddenFields() async throws {
        let store = try BackgroundStore(modelContainer: ModelContainerFactory.inMemory())
        let keeper = Job(jobNumber: 1, company: "Acme (hand-typed)", title: "Kept Title")
        keeper.manualFieldOverridesJSON = manualFieldOverrideJSON(["company"])
        keeper.extractedJSON = "{\"kept\":true}"
        keeper.extractionModel = "kept-model"
        keeper.extractionStatus = .succeeded

        let fork = Job(jobNumber: 2, company: "Render", title: "Other Title", location: "Remote")
        fork.extractedJSON = "{\"fork\":true}"
        fork.extractionModel = "fork-model"
        fork.extractionStatus = .succeeded

        try await store.insert(keeper)
        try await store.insert(fork)

        let result = try await store.mergeJob(from: 2, into: 1)

        XCTAssertEqual(result.fieldsCopied, ["location"], "only the genuinely missing field is filled")
        let mergedJobs = try await store.fetch(FetchDescriptor<Job>())
        let merged = try XCTUnwrap(mergedJobs.first)
        XCTAssertEqual(merged.company, "Acme (hand-typed)", "a manual override is never clobbered")
        XCTAssertEqual(merged.title, "Kept Title", "an already-populated field is never clobbered")
        XCTAssertEqual(merged.location, "Remote")
        XCTAssertEqual(merged.extractedJSON, "{\"kept\":true}", "the keeper's own extraction wins")
        XCTAssertEqual(merged.extractionModel, "kept-model", "provenance stays consistent with the JSON")
    }

    func testMergeJob_unknownJobNumberThrowsAndDeletesNothing() async throws {
        let store = try BackgroundStore(modelContainer: ModelContainerFactory.inMemory())
        try await store.insert(Job(jobNumber: 1))

        do {
            _ = try await store.mergeJob(from: 999, into: 1)
            XCTFail("merging from a job number that doesn't exist must throw")
        } catch {
            // expected
        }
        let jobs = try await store.fetch(FetchDescriptor<Job>())
        XCTAssertEqual(jobs.count, 1, "a failed merge must not delete anything")
    }
}
