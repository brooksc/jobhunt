import SwiftData
import XCTest
@testable import JobhuntCore

// MARK: - Stub LLM provider (never actually called in these tests)

private struct NoOpProvider: LLMProvider {
    let id: String = "noop"
    let concurrencyLimit: Int = 1
    func complete(_: ChatRequest) async throws -> ChatResponse {
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

        let payload = CapturePayload(
            url: "https://example.com",
            pageTitle: "Title",
            selectedText: nil,
            visibleText: nil
        )
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

        let payload = CapturePayload(
            url: "https://example.com",
            pageTitle: "Title",
            selectedText: "  ",
            visibleText: "  "
        )
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

        let job1 = Job(id: "job-1", jobNumber: 1, company: "Acme", title: "Engineer", status: .pursuing)
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
        let job = Job(id: "job-esc", jobNumber: 3, company: "Acme, Inc.", title: "Engineer, Senior", status: .pursuing)
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

    // MARK: - testClearDataQualityReview_onlyDeletesTargetedReview

    func testClearDataQualityReview_onlyDeletesTargetedReview() async throws {
        let container = try ModelContainerFactory.inMemory()
        let store = makeStore(container)
        let queue = makeQueue(container)
        let svc = JobService(store: store, queue: queue)

        // Ingest two jobs
        let payload1 = CapturePayload(url: "https://example.com/j/1", pageTitle: "Job One", selectedText: nil, visibleText: "Text one")
        let payload2 = CapturePayload(url: "https://example.com/j/2", pageTitle: "Job Two", selectedText: nil, visibleText: "Text two")
        let r1 = try await svc.ingestCapture(payload1)
        let r2 = try await svc.ingestCapture(payload2)

        // Mark both as reviewed
        let ctx = ModelContext(container)
        let jobs = try ctx.fetch(FetchDescriptor<Job>(sortBy: [SortDescriptor(\.createdAt)]))
        XCTAssertEqual(jobs.count, 2)
        let job1 = jobs[0], job2 = jobs[1]

        try await svc.markDataQualityReviewed(jobID: job1.id, notes: nil)
        try await svc.markDataQualityReviewed(jobID: job2.id, notes: nil)

        // Verify both have reviews
        let reviewsBefore = try ctx.fetch(FetchDescriptor<DataQualityReview>())
        XCTAssertEqual(reviewsBefore.count, 2, "Both jobs should have reviews")

        // Clear only job1's review
        try await svc.clearDataQualityReview(jobID: job1.id)

        // Only job2's review should remain
        let reviewsAfter = try ctx.fetch(FetchDescriptor<DataQualityReview>())
        XCTAssertEqual(reviewsAfter.count, 1, "Only job2's review should remain after clearing job1")
        XCTAssertEqual(reviewsAfter.first?.job?.id, job2.id, "Remaining review belongs to job2")
    }

    // MARK: - MCP read query tests

    func testListJobs_noFilter_returnsAllUpToLimit() async throws {
        let container = try ModelContainerFactory.inMemory()
        let store = makeStore(container)
        let queue = makeQueue(container)
        let svc = JobService(store: store, queue: queue)

        for i in 1...5 {
            let p = CapturePayload(url: "https://example.com/j/\(i)", pageTitle: "Job \(i)", visibleText: "text")
            _ = try await svc.ingestCapture(p)
        }

        let records = try await svc.listJobs(status: nil, limit: 3)
        XCTAssertEqual(records.count, 3)
    }

    func testListJobs_statusFilter_returnsOnlyMatching() async throws {
        let container = try ModelContainerFactory.inMemory()
        let store = makeStore(container)
        let queue = makeQueue(container)
        let svc = JobService(store: store, queue: queue)

        let p1 = CapturePayload(url: "https://example.com/j/1", pageTitle: "Job 1", visibleText: "text")
        let p2 = CapturePayload(url: "https://example.com/j/2", pageTitle: "Job 2", visibleText: "text")
        let r1 = try await svc.ingestCapture(p1)
        _ = try await svc.ingestCapture(p2)

        try await svc.setStatus(.pursuing, for: r1.captureID.replacingOccurrences(of: "cap-", with: "job-"))
        // Directly set one job to pursuing via store
        let all = try await store.fetch(FetchDescriptor<Job>())
        let job1 = all.first(where: { $0.jobNumber == r1.jobNumber })!
        try await svc.setStatus(.pursuing, for: job1.id)

        let pursuing = try await svc.listJobs(status: "pursuing", limit: 50)
        XCTAssertTrue(pursuing.allSatisfy { $0.status == .pursuing })
    }

    func testGetJob_found() async throws {
        let container = try ModelContainerFactory.inMemory()
        let store = makeStore(container)
        let queue = makeQueue(container)
        let svc = JobService(store: store, queue: queue)

        let p = CapturePayload(url: "https://example.com/jobs/42", pageTitle: "My Job", visibleText: "description")
        let result = try await svc.ingestCapture(p)

        let record = try await svc.getJob(byNumber: result.jobNumber)
        XCTAssertNotNil(record)
        XCTAssertEqual(record?.jobNumber, result.jobNumber)
        XCTAssertEqual(record?.pageTitle, "My Job")
        XCTAssertEqual(record?.sourceURL, "https://example.com/jobs/42")
    }

    func testGetJob_notFound_returnsNil() async throws {
        let container = try ModelContainerFactory.inMemory()
        let store = makeStore(container)
        let queue = makeQueue(container)
        let svc = JobService(store: store, queue: queue)

        let record = try await svc.getJob(byNumber: 9999)
        XCTAssertNil(record)
    }

    func testConcurrentIngest_assignsDistinctJobNumbers() async throws {
        let container = try ModelContainerFactory.inMemory()
        let store = makeStore(container)
        let queue = makeQueue(container)
        let svc = JobService(store: store, queue: queue)

        let payloads = (1...5).map { i in
            CapturePayload(
                url: "https://example.com/j/\(i)",
                pageTitle: "Job \(i)",
                visibleText: "description \(i)"
            )
        }

        // Launch all 5 ingestions concurrently
        let results = try await withThrowingTaskGroup(of: IngestResult.self) { group in
            for p in payloads { group.addTask { try await svc.ingestCapture(p) } }
            var out: [IngestResult] = []
            for try await r in group { out.append(r) }
            return out
        }

        let numbers = results.filter { !$0.isDuplicate }.map(\.jobNumber)
        XCTAssertEqual(Set(numbers).count, numbers.count, "Every concurrent ingest must get a unique jobNumber")
        XCTAssertEqual(numbers.count, 5)
    }

    func testAtomicIngest_createsCaptureJobAndLLMRequest() async throws {
        let container = try ModelContainerFactory.inMemory()
        let store = makeStore(container)
        let queue = makeQueue(container)
        let svc = JobService(store: store, queue: queue)

        let payload = CapturePayload(
            url: "https://example.com/atomic",
            pageTitle: "Atomic Job",
            visibleText: "some text"
        )
        _ = try await svc.ingestCapture(payload)

        let ctx = ModelContext(container)
        let jobs = try ctx.fetch(FetchDescriptor<Job>())
        let captures = try ctx.fetch(FetchDescriptor<Capture>())
        let requests = try ctx.fetch(FetchDescriptor<LLMRequest>())

        XCTAssertEqual(jobs.count, 1)
        XCTAssertEqual(captures.count, 1)
        XCTAssertEqual(requests.count, 1, "Extraction LLMRequest must be created atomically with Capture+Job")
        XCTAssertEqual(requests.first?.job?.id, jobs.first?.id)
    }

    func testWorkflowSnapshot_countsJobsAndSites() async throws {
        let container = try ModelContainerFactory.inMemory()
        let store = makeStore(container)
        let queue = makeQueue(container)
        let svc = JobService(store: store, queue: queue)

        for i in 1...3 {
            let p = CapturePayload(url: "https://example.com/j/\(i)", pageTitle: "Job \(i)", visibleText: "t")
            _ = try await svc.ingestCapture(p)
        }

        let snap = try await svc.workflowSnapshot()
        XCTAssertEqual(snap.jobsTotal, 3)
        XCTAssertFalse(snap.statusCounts.isEmpty)
    }
}
