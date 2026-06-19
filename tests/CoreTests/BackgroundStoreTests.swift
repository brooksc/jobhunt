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

// MARK: - Minimal no-op provider (local to this file)

private struct NoOpLLMProvider: LLMProvider {
    let id: String = "noop"
    let concurrencyLimit: Int = 1
    func complete(_: ChatRequest) async throws -> ChatResponse {
        throw LLMProviderError.httpError(statusCode: 503, body: "no-op")
    }
}
