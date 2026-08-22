import SwiftData
import XCTest
@testable import JobhuntCore

/// `Dictionary(uniqueKeysWithValues:)` TRAPS on a duplicate key, and setJobStatus built one from
/// every job's id — so two rows sharing an id would take the whole process down on an ordinary status
/// change, with nothing to diagnose from. A repeated URL query parameter killed the app exactly this
/// way once already; this is the same construct applied to runtime data (TASK-678).
final class DuplicateJobIDTests: XCTestCase {
    /// Two rows with one id: the operation is refused with a diagnosable error, not a crash.
    func testChangingAnAmbiguousJobThrowsInsteadOfTrapping() async throws {
        let container = try ModelContainerFactory.inMemory()
        let store = BackgroundStore(modelContainer: container)
        let sharedID = "duplicated-id"
        let first = Job(jobNumber: 1, title: "First")
        first.id = sharedID
        let second = Job(jobNumber: 2, title: "Second")
        second.id = sharedID
        try await store.insert(first)
        try await store.insert(second)

        do {
            try await store.setJobStatus(.applied, jobIDs: [sharedID])
            XCTFail("changing a job whose id matches two rows must not silently pick one")
        } catch let error as BackgroundStoreError {
            guard case let .duplicateJobIDs(ids) = error else {
                return XCTFail("expected duplicateJobIDs, got \(error)")
            }
            XCTAssertEqual(ids, [sharedID])
            let message = try XCTUnwrap(error.errorDescription)
            XCTAssertTrue(message.contains(sharedID), "the message must name the id: \(message)")
        }
    }

    /// A duplicate elsewhere in the store must not block unrelated work — the row being changed is
    /// unambiguous, so the change is safe.
    func testADuplicateElsewhereDoesNotBlockAnUnrelatedChange() async throws {
        let container = try ModelContainerFactory.inMemory()
        let store = BackgroundStore(modelContainer: container)
        let dupA = Job(jobNumber: 1, title: "Dup A")
        dupA.id = "shared"
        let dupB = Job(jobNumber: 2, title: "Dup B")
        dupB.id = "shared"
        let clean = Job(jobNumber: 3, title: "Clean")
        for job in [dupA, dupB, clean] {
            try await store.insert(job)
        }

        try await store.setJobStatus(.applied, jobIDs: [clean.id])

        let jobs = try await store.fetch(FetchDescriptor<Job>())
        let updated = try XCTUnwrap(jobs.first { $0.jobNumber == 3 })
        XCTAssertEqual(updated.status, .applied)
    }

    /// The ordinary path is unaffected.
    func testNormalStatusChangeStillWorks() async throws {
        let container = try ModelContainerFactory.inMemory()
        let store = BackgroundStore(modelContainer: container)
        let job = Job(jobNumber: 1, title: "T")
        try await store.insert(job)

        try await store.setJobStatus(.pursuing, jobIDs: [job.id])
        let jobs = try await store.fetch(FetchDescriptor<Job>())
        XCTAssertEqual(jobs.first?.status, .pursuing)
    }

    /// An id that matches nothing is still reported as missing, not as a duplicate.
    func testUnknownIDStillReportsNotFound() async throws {
        let container = try ModelContainerFactory.inMemory()
        let store = BackgroundStore(modelContainer: container)
        do {
            try await store.setJobStatus(.applied, jobIDs: ["nope"])
            XCTFail("expected notFound")
        } catch let error as BackgroundStoreError {
            guard case .notFound = error else {
                return XCTFail("expected notFound, got \(error)")
            }
        }
    }
}
