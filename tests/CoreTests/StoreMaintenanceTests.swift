import SwiftData
import XCTest
@testable import JobhuntCore

/// Tests for BackgroundStore maintenance ops run out-of-band via JobhuntMigrator:
/// recomputeAllJobFitMirrors and pruneOrphanRequestAttempts.
final class StoreMaintenanceTests: XCTestCase {
    func testRecomputeFitMirrors_correctsDriftAndCountsOnlyChanged() async throws {
        let store = BackgroundStore(modelContainer: try ModelContainerFactory.inMemory())
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
        for m in [stale, ok] { try await store.insert(m) }
        for m in [s1, s2] { try await store.insert(m) }

        let changed = try await store.recomputeAllJobFitMirrors()
        XCTAssertEqual(changed, 1, "only the drifted job is corrected")

        let jobs = try await store.fetch(FetchDescriptor<Job>())
        let byNum = Dictionary(uniqueKeysWithValues: jobs.map { ($0.jobNumber, $0) })
        XCTAssertEqual(byNum[1]?.fitScore, 88, "drift corrected to best resume-linked score")
        XCTAssertEqual(byNum[2]?.fitScore, 80, "consistent job unchanged")
    }

    func testPruneOrphanAttempts_deletesOnlyRequestlessAttempts() async throws {
        let store = BackgroundStore(modelContainer: try ModelContainerFactory.inMemory())

        // Linked attempt (has a parent request).
        let req = LLMRequest(requestType: .extract, status: .succeeded)
        req.finishedAt = Date()
        let linked = LLMRequestAttempt(requestType: .extract, attempt: 1, status: .succeeded, modelRequested: "lmstudio")
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
        let store = BackgroundStore(modelContainer: try ModelContainerFactory.inMemory())
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
}
