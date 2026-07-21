import SwiftData
import XCTest
@testable import JobhuntCore

// MARK: - BackgroundStore updateOne / deleteOne guard tests

final class BackgroundStoreOneTests: XCTestCase {
    private func makeStore(_ container: ModelContainer) -> BackgroundStore {
        BackgroundStore(modelContainer: container)
    }

    // MARK: updateOne

    func testUpdateOne_noMatch_throwsNotFound() async throws {
        let container = try ModelContainerFactory.inMemory()
        let store = makeStore(container)
        let missingID = "missing-id"
        do {
            try await store
                .updateOne(Job.self, predicate: #Predicate { $0.id == missingID }, id: missingID) { $0.company = "X" }
            XCTFail("Expected notFound")
        } catch BackgroundStoreError.notFound {
            // expected
        }
    }

    func testUpdateOne_exactlyOne_succeeds() async throws {
        let container = try ModelContainerFactory.inMemory()
        let store = makeStore(container)
        let jobID = UUID().uuidString
        let job = Job(id: jobID, jobNumber: 1, company: "Old")
        try await store.insert(job)

        try await store.updateOne(Job.self, predicate: #Predicate { $0.id == jobID }, id: jobID) { $0.company = "New" }

        let jobs = try await store.fetch(FetchDescriptor<Job>())
        XCTAssertEqual(jobs.first?.company, "New")
    }

    func testUpdateOne_multipleMatches_throwsMultipleMatches() async throws {
        let container = try ModelContainerFactory.inMemory()
        let store = makeStore(container)
        // Insert two jobs sharing the same company so the predicate matches both
        let sharedCompany = "SharedCo"
        let job1 = Job(id: UUID().uuidString, jobNumber: 1, company: sharedCompany)
        let job2 = Job(id: UUID().uuidString, jobNumber: 2, company: sharedCompany)
        try await store.insertBatch([job1, job2])

        do {
            try await store.updateOne(
                Job.self,
                predicate: #Predicate { $0.company == sharedCompany },
                id: sharedCompany
            ) { $0.title = "X" }
            XCTFail("Expected multipleMatches")
        } catch let BackgroundStoreError.multipleMatches(count) {
            XCTAssertEqual(count, 2)
        }
    }

    // MARK: deleteOne

    func testDeleteOne_noMatch_throwsNotFound() async throws {
        let container = try ModelContainerFactory.inMemory()
        let store = makeStore(container)
        let missingID = "missing-id"
        do {
            try await store.deleteOne(Job.self, predicate: #Predicate { $0.id == missingID }, id: missingID)
            XCTFail("Expected notFound")
        } catch BackgroundStoreError.notFound {
            // expected
        }
    }

    func testDeleteOne_exactlyOne_succeeds() async throws {
        let container = try ModelContainerFactory.inMemory()
        let store = makeStore(container)
        let jobID = UUID().uuidString
        let job = Job(id: jobID, jobNumber: 1)
        try await store.insert(job)

        try await store.deleteOne(Job.self, predicate: #Predicate { $0.id == jobID }, id: jobID)

        let jobs = try await store.fetch(FetchDescriptor<Job>())
        XCTAssertEqual(jobs.count, 0)
    }

    func testDeleteOne_multipleMatches_throwsMultipleMatches() async throws {
        let container = try ModelContainerFactory.inMemory()
        let store = makeStore(container)
        let sharedCompany = "SharedCo"
        let job1 = Job(id: UUID().uuidString, jobNumber: 1, company: sharedCompany)
        let job2 = Job(id: UUID().uuidString, jobNumber: 2, company: sharedCompany)
        try await store.insertBatch([job1, job2])

        do {
            try await store.deleteOne(
                Job.self,
                predicate: #Predicate { $0.company == sharedCompany },
                id: sharedCompany
            )
            XCTFail("Expected multipleMatches")
        } catch let BackgroundStoreError.multipleMatches(count) {
            XCTAssertEqual(count, 2)
            // Both rows must still exist — nothing was deleted
            let jobs = try await store.fetch(FetchDescriptor<Job>())
            XCTAssertEqual(jobs.count, 2)
        }
    }
}

// MARK: - BackgroundStore not-found regression tests

final class BackgroundStoreNotFoundTests: XCTestCase {
    private func makeStore(_ container: ModelContainer) -> BackgroundStore {
        BackgroundStore(modelContainer: container)
    }

    private func makeQueue(_ container: ModelContainer) -> QueueActor {
        QueueActor(
            store: makeStore(container),
            isPaused: { false },
            onSetPaused: { _ in },
            readExtractionSettings: {
                ExtractionSettings(
                    llmModel: "", preferredLocations: "",
                    locationFilterEnabled: false,
                    locationAllowRemote: true, locationAllowHybrid: true, locationAllowOnsite: true
                )
            },
            providerFactory: { NoOpLLMProvider() }
        )
    }

    func testSetStatus_missingJobID_throws() async throws {
        let container = try ModelContainerFactory.inMemory()
        let store = makeStore(container)
        let svc = JobService(store: store, queue: makeQueue(container))

        do {
            try await svc.setStatus(.pursuing, for: "nonexistent-job-id")
            XCTFail("Expected jobNotFound error")
        } catch JobServiceError.jobNotFound {
            // expected
        }
    }

    func testDelete_missingJobID_throws() async throws {
        let container = try ModelContainerFactory.inMemory()
        let store = makeStore(container)
        let svc = JobService(store: store, queue: makeQueue(container))

        do {
            try await svc.delete(jobID: "nonexistent-job-id")
            XCTFail("Expected notFound error")
        } catch BackgroundStoreError.notFound {
            // expected
        }
    }
}

// MARK: - Incremental duplicate detection + fit guard (TASK-611)

final class BackgroundStoreDuplicateGuardTests: XCTestCase {
    func testDetectDuplicateForJob_flagsSecondCopy_andBlocksFit() async throws {
        let container = try ModelContainerFactory.inMemory()
        let store = BackgroundStore(modelContainer: container)

        let hash = "dup_hash"
        let desc = "Shared boilerplate duplicate listing carrying sufficient distinct meaningful unique tokens here"
        func makeJob(id: String, num: Int, url: String) -> (Job, Capture) {
            let cap = Capture(url: url, pageTitle: "Software Engineer", rawHash: "rh_\(id)", cleanedHash: hash)
            cap.cleanedDescription = desc
            let job = Job(id: id, company: "AcmeCorp", title: "Software Engineer", extractionStatus: .succeeded)
            job.jobNumber = num
            job.capture = cap
            return (job, cap)
        }
        let (orig, origCap) = makeJob(id: "orig", num: 1, url: "https://acme.com/job")
        let (cand, candCap) = makeJob(id: "cand", num: 2, url: "https://greenhouse.io/acme/job")
        for model in [origCap, candCap] as [any PersistentModel] {
            try await store.insert(model)
        }
        for model in [orig, cand] as [any PersistentModel] {
            try await store.insert(model)
        }

        // The later copy is flagged a duplicate of the earlier one.
        let flagged = try await store.detectDuplicateForJob(jobID: "cand")
        XCTAssertTrue(flagged)
        let jobs = try await store.fetch(FetchDescriptor<Job>())
        let candidate = jobs.first { $0.id == "cand" }
        XCTAssertEqual(candidate?.status, .duplicate)
        XCTAssertEqual(candidate?.duplicateOfJobID, "orig")

        // Fit scoring is blocked for the duplicate — no wasted LLM call.
        let queued = try await store.enqueueFitForActiveResumes(jobID: "cand")
        XCTAssertEqual(queued, 0, "a duplicate must not enqueue fit work")

        // The canonical original is NOT flagged.
        let flaggedOrig = try await store.detectDuplicateForJob(jobID: "orig")
        XCTAssertFalse(flaggedOrig)
    }
}

// MARK: - Minimal no-op provider (local to this file)

private struct NoOpLLMProvider: LLMProvider {
    let id: String = "noop"
    let concurrencyLimit: Int = 1
    func complete(_: ChatRequest) async throws -> ChatResponse {
        throw LLMProviderError.httpError(statusCode: 503, body: "no-op")
    }
}
