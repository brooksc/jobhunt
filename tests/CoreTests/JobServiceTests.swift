import XCTest
import SwiftData
@testable import JobhuntCore

// MARK: - Stub LLM provider (never actually called in these tests)

private struct NoOpProvider: LLMProvider {
    let id: String = "noop"
    let concurrencyLimit: Int = 1
    func complete(_ request: ChatRequest) async throws -> ChatResponse {
        throw LLMProviderError.httpError(statusCode: 503, body: "no-op")
    }
}

// MARK: - Helpers

private func makeStore(_ container: ModelContainer) -> BackgroundStore {
    BackgroundStore(modelContainer: container)
}

private func makeQueue(_ container: ModelContainer) -> QueueActor {
    let context = ModelContext(container)
    let settings = SettingsStore(modelContext: context)
    return QueueActor(store: makeStore(container), settings: settings, providerFactory: { NoOpProvider() })
}

// MARK: - JobServiceTests

final class JobServiceTests: XCTestCase {

    // MARK: - testIngestNewCapture

    func testIngestNewCapture() async throws {
        let container = try ModelContainerFactory.inMemory()
        let store = makeStore(container)
        let queue = makeQueue(container)
        let svc = JobService(store: store, queue: queue)

        let payload = CapturePayload(
            url: "https://example.com/jobs/1",
            pageTitle: "Senior Engineer",
            selectedText: nil,
            visibleText: "We are hiring a senior engineer to join our team."
        )

        let result = try await svc.ingestCapture(payload)

        XCTAssertFalse(result.isDuplicate)
        XCTAssertEqual(result.jobNumber, 1)
        XCTAssertFalse(result.captureID.isEmpty)

        // Verify job persisted
        let allJobs = try await store.fetch(FetchDescriptor<Job>())
        XCTAssertEqual(allJobs.count, 1)
        XCTAssertEqual(allJobs.first?.jobNumber, 1)
    }

    // MARK: - testIngestDuplicateCapture

    func testIngestDuplicateCapture() async throws {
        let container = try ModelContainerFactory.inMemory()
        let store = makeStore(container)
        let queue = makeQueue(container)
        let svc = JobService(store: store, queue: queue)

        let payload1 = CapturePayload(
            url: "https://example.com/jobs/1",
            pageTitle: "Software Engineer",
            selectedText: nil,
            visibleText: "Join our engineering team as a software engineer."
        )
        let result1 = try await svc.ingestCapture(payload1)
        XCTAssertFalse(result1.isDuplicate)

        // Same URL + identical content → rawHash collision → isDuplicate=true
        let payload2 = CapturePayload(
            url: "https://example.com/jobs/1",
            pageTitle: "Software Engineer",
            selectedText: nil,
            visibleText: "Join our engineering team as a software engineer."
        )
        let result2 = try await svc.ingestCapture(payload2)
        XCTAssertTrue(result2.isDuplicate)
        // Should return the original captureID
        XCTAssertEqual(result2.captureID, result1.captureID)
    }

    // MARK: - testIngestValidation

    func testIngestValidation_missingURL() async throws {
        let container = try ModelContainerFactory.inMemory()
        let store = makeStore(container)
        let queue = makeQueue(container)
        let svc = JobService(store: store, queue: queue)

        let payload = CapturePayload(url: "  ", pageTitle: "Title", visibleText: "some text")
        do {
            _ = try await svc.ingestCapture(payload)
            XCTFail("Expected error")
        } catch JobServiceError.missingURL {
            // Expected
        }
    }

    func testIngestValidation_missingTitle() async throws {
        let container = try ModelContainerFactory.inMemory()
        let store = makeStore(container)
        let queue = makeQueue(container)
        let svc = JobService(store: store, queue: queue)

        let payload = CapturePayload(url: "https://example.com", pageTitle: "", visibleText: "some text")
        do {
            _ = try await svc.ingestCapture(payload)
            XCTFail("Expected error")
        } catch JobServiceError.missingPageTitle {
            // Expected
        }
    }

    func testIngestValidation_missingText() async throws {
        let container = try ModelContainerFactory.inMemory()
        let store = makeStore(container)
        let queue = makeQueue(container)
        let svc = JobService(store: store, queue: queue)

        let payload = CapturePayload(url: "https://example.com", pageTitle: "Title", selectedText: nil, visibleText: nil)
        do {
            _ = try await svc.ingestCapture(payload)
            XCTFail("Expected error")
        } catch JobServiceError.missingText {
            // Expected
        }
    }

    func testIngestValidation_emptyText() async throws {
        let container = try ModelContainerFactory.inMemory()
        let store = makeStore(container)
        let queue = makeQueue(container)
        let svc = JobService(store: store, queue: queue)

        let payload = CapturePayload(url: "https://example.com", pageTitle: "Title", selectedText: "  ", visibleText: "  ")
        do {
            _ = try await svc.ingestCapture(payload)
            XCTFail("Expected error")
        } catch JobServiceError.missingText {
            // Expected
        }
    }

    // MARK: - testSetStatus

    func testSetStatus() async throws {
        let container = try ModelContainerFactory.inMemory()
        let store = makeStore(container)
        let queue = makeQueue(container)
        let svc = JobService(store: store, queue: queue)

        let payload = CapturePayload(
            url: "https://example.com/jobs/42",
            pageTitle: "Product Manager",
            visibleText: "We are looking for an experienced product manager to lead our team."
        )
        let result = try await svc.ingestCapture(payload)

        // Find job by number
        var descriptor = FetchDescriptor<Job>()
        let jobs = try await store.fetch(descriptor)
        let job = try XCTUnwrap(jobs.first(where: { $0.jobNumber == result.jobNumber }))
        let jobID = job.id

        try await svc.setStatus(.applied, for: jobID)

        let updated = try await store.fetch(FetchDescriptor<Job>(predicate: #Predicate { $0.id == jobID }))
        XCTAssertEqual(updated.first?.status, .applied)
    }

    // MARK: - testCSVColumns

    func testCSVColumns() async throws {
        let container = try ModelContainerFactory.inMemory()
        let store = makeStore(container)

        let job1 = Job(id: "job-1", jobNumber: 1, company: "Acme", title: "Engineer", status: .saved)
        let job2 = Job(id: "job-2", jobNumber: 2, company: "Beta", title: "Designer", status: .applied)
        try await store.insertBatch([job1, job2])

        let jobs = [job1, job2]
        let csv = ExportService.jobsCSV(jobs: jobs)
        let lines = csv.components(separatedBy: "\n").filter { !$0.isEmpty }

        // 1 header + 2 data rows
        XCTAssertEqual(lines.count, 3)

        let header = lines[0]
        let columns = header.components(separatedBy: ",")
        XCTAssertEqual(columns.count, 19, "Expected 19 CSV columns, got \(columns.count): \(header)")
    }

    // MARK: - testCSVEscaping

    func testCSVEscaping() async throws {
        let container = try ModelContainerFactory.inMemory()
        let store = makeStore(container)

        // Job with comma in title
        let job = Job(id: "job-esc", jobNumber: 3, company: "Acme, Inc.", title: "Engineer, Senior", status: .saved)
        try await store.insert(job)

        let csv = ExportService.jobsCSV(jobs: [job])
        let lines = csv.components(separatedBy: "\n").filter { !$0.isEmpty }
        XCTAssertEqual(lines.count, 2) // header + 1 row

        // Fields with commas must be quoted
        let dataRow = lines[1]
        XCTAssertTrue(dataRow.contains("\"Acme, Inc.\""), "Company with comma should be quoted: \(dataRow)")
        XCTAssertTrue(dataRow.contains("\"Engineer, Senior\""), "Title with comma should be quoted: \(dataRow)")
    }

    // MARK: - testCSVQuoteEscaping

    func testCSVQuoteEscaping() {
        // Internal double-quotes must be doubled
        let result = ExportService.escapeCsv("say \"hello\"")
        XCTAssertEqual(result, "\"say \"\"hello\"\"\"")
    }
}
