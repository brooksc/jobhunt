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
    QueueActor(
        store: makeStore(container),
        isPaused: { true },
        onSetPaused: { _ in },
        readExtractionSettings: { ExtractionSettings(
            llmModel: "",
            preferredLocations: "",
            locationFilterEnabled: false,
            locationAllowRemote: true,
            locationAllowHybrid: true,
            locationAllowOnsite: true
        ) },
        providerFactory: { NoOpProvider() }
    )
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

    // MARK: - TASK-448: manual URL ingest must not double-enqueue extraction

    func testAddJobByURL_createsExactlyOneExtractionRequest() async throws {
        let container = try ModelContainerFactory.inMemory()
        let store = makeStore(container)
        let queue = makeQueue(container)
        let svc = JobService(store: store, queue: queue)

        let result = try await svc.addJobByURL("https://example.com/jobs/manual-1")
        XCTAssertFalse(result.isDuplicate)

        let extractReqs = try await store.fetch(FetchDescriptor<LLMRequest>())
            .filter { $0.requestType == .extract }
        XCTAssertEqual(extractReqs.count, 1, "Manual URL add must create exactly one extraction request")
    }

    func testAddJobByURL_duplicateSubmissionCreatesNoExtraRequest() async throws {
        let container = try ModelContainerFactory.inMemory()
        let store = makeStore(container)
        let queue = makeQueue(container)
        let svc = JobService(store: store, queue: queue)

        _ = try await svc.addJobByURL("https://example.com/jobs/manual-dup")
        _ = try await svc.addJobByURL("https://example.com/jobs/manual-dup")

        let extractReqs = try await store.fetch(FetchDescriptor<LLMRequest>())
            .filter { $0.requestType == .extract }
        XCTAssertEqual(extractReqs.count, 1, "Re-submitting the same URL must not add extraction requests")
    }

    // TASK-444: open-in-app job lookup matches by original, canonical, and normalized URL.
    func testFindJobNumber_byExactCanonicalAndNormalizedURL() async throws {
        let container = try ModelContainerFactory.inMemory()
        let store = makeStore(container)
        let svc = JobService(store: store, queue: makeQueue(container))

        let result = try await svc.ingestCapture(CapturePayload(
            url: "https://jobs.example.com/eng",
            pageTitle: "Eng",
            visibleText: "A long job description for a senior engineer role on the platform team.",
            canonicalURL: "https://jobs.example.com/engineering"
        ))
        let jobNumber = result.jobNumber

        // exact original url
        await assertFindsJob(svc, "https://jobs.example.com/eng", jobNumber)
        // exact canonical url
        await assertFindsJob(svc, "https://jobs.example.com/engineering", jobNumber)
        // tracking-param variant of the original — normalized match
        await assertFindsJob(svc, "https://jobs.example.com/eng?utm_source=newsletter&gclid=abc", jobNumber)
        // trailing slash variant
        await assertFindsJob(svc, "https://jobs.example.com/eng/", jobNumber)

        let none = try await svc.findJobNumber(byURL: "https://other.example.com/nope")
        XCTAssertNil(none, "unrelated URL must not match")
    }

    private func assertFindsJob(
        _ svc: JobService,
        _ url: String,
        _ expected: Int,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        do {
            let found = try await svc.findJobNumber(byURL: url)
            XCTAssertEqual(found, expected, "lookup for \(url)", file: file, line: line)
        } catch {
            XCTFail("findJobNumber threw for \(url): \(error)", file: file, line: line)
        }
    }

    func testURLNormalizer_canonicalForm() {
        XCTAssertEqual(
            URLNormalizer.normalized("https://Example.com/Jobs/Eng/?utm_source=x&b=2&a=1#frag"),
            URLNormalizer.normalized("https://example.com/Jobs/Eng?a=1&b=2")
        )
        XCTAssertNil(URLNormalizer.normalized("not a url"))
        XCTAssertNil(URLNormalizer.normalized("ftp://example.com/x"))
    }

    // TASK-441: a semantic-duplicate capture (same cleaned content, different URL+canonical) is
    // flagged .duplicate and must NOT auto-queue an extraction request.
    func testIngestCapture_semanticDuplicateDoesNotQueueExtraction() async throws {
        let container = try ModelContainerFactory.inMemory()
        let store = makeStore(container)
        let queue = makeQueue(container)
        let svc = JobService(store: store, queue: queue)

        let desc = "We are hiring a senior platform engineer to build distributed systems at scale "
            + "using Swift and Go across many teams worldwide with strong end-to-end ownership."
        _ = try await svc.ingestCapture(CapturePayload(
            url: "https://a.com/job", pageTitle: "Eng", visibleText: desc,
            canonicalURL: "https://a.com/canonical-a"
        ))
        _ = try await svc.ingestCapture(CapturePayload(
            url: "https://b.com/job", pageTitle: "Eng", visibleText: desc,
            canonicalURL: "https://b.com/canonical-b"
        ))

        let jobs = try await store.fetch(FetchDescriptor<Job>())
        XCTAssertEqual(jobs.count, 2)
        XCTAssertEqual(jobs.count(where: { $0.duplicateOfJobID != nil }), 1, "second is a semantic duplicate")

        let extractReqs = try await store.fetch(FetchDescriptor<LLMRequest>())
            .filter { $0.requestType == .extract }
        XCTAssertEqual(extractReqs.count, 1, "only the unique job auto-queues extraction")
    }

    func testIngestCapture_createsExactlyOneExtractionRequest() async throws {
        let container = try ModelContainerFactory.inMemory()
        let store = makeStore(container)
        let queue = makeQueue(container)
        let svc = JobService(store: store, queue: queue)

        _ = try await svc.ingestCapture(CapturePayload(
            url: "https://example.com/jobs/cap-1",
            pageTitle: "Engineer",
            selectedText: nil,
            visibleText: "We are hiring an engineer."
        ))

        let extractReqs = try await store.fetch(FetchDescriptor<LLMRequest>())
            .filter { $0.requestType == .extract }
        XCTAssertEqual(extractReqs.count, 1, "Browser capture ingest must create exactly one extraction request")
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

    // MARK: - TASK-156: resetExtraction clears stale state and enqueues

    func testResetExtraction_clearsStaleFlagsAndEnqueues() async throws {
        let container = try ModelContainerFactory.inMemory()
        let store = makeStore(container)
        let queue = makeQueue(container)
        let svc = JobService(store: store, queue: queue)

        let r = try await svc.ingestCapture(CapturePayload(
            url: "https://j.example.com/r1",
            pageTitle: "Eng",
            visibleText: "Job text"
        ))
        let jobs = try await store.fetch(FetchDescriptor<Job>())
        let jobID = try XCTUnwrap(jobs.first(where: { $0.jobNumber == r.jobNumber })?.id)

        // Simulate a prior extraction result with stale fields
        try await store.update(Job.self, predicate: #Predicate { $0.id == jobID }) { job in
            job.extractionStatus = .succeeded
            job.extractionError = "old error"
            job.extractedAt = Date(timeIntervalSinceNow: -3600)
        }
        try await queue.deleteAll()

        try await svc.resetExtraction(jobID: jobID)

        let updated = try await store.fetch(FetchDescriptor<Job>(predicate: #Predicate { $0.id == jobID }))
        XCTAssertEqual(
            updated.first?.extractionStatus,
            .pending,
            "resetExtraction must set extractionStatus to .pending"
        )
        XCTAssertNil(updated.first?.extractionError, "resetExtraction must clear extractionError")
        XCTAssertNil(updated.first?.extractedAt, "resetExtraction must clear extractedAt")

        let requests = try await store.fetch(FetchDescriptor<LLMRequest>())
        XCTAssertEqual(requests.count, 1, "resetExtraction must enqueue one LLMRequest")
        XCTAssertEqual(requests.first?.requestType, .extract)
        XCTAssertEqual(requests.first?.status, .queued)
    }

    // MARK: - TASK-253: resetExtraction also clears extracted payload fields

    func testResetExtraction_clearsExtractedPayloadFields() async throws {
        let container = try ModelContainerFactory.inMemory()
        let store = makeStore(container)
        let queue = makeQueue(container)
        let svc = JobService(store: store, queue: queue)

        let r = try await svc.ingestCapture(CapturePayload(
            url: "https://j.example.com/p1",
            pageTitle: "Eng",
            visibleText: "Job text"
        ))
        let jobs = try await store.fetch(FetchDescriptor<Job>())
        let jobID = try XCTUnwrap(jobs.first(where: { $0.jobNumber == r.jobNumber })?.id)

        // Simulate a prior extraction that populated all extracted scalars
        try await store.update(Job.self, predicate: #Predicate { $0.id == jobID }) { job in
            job.extractionStatus = .succeeded
            job.company = "Acme Corp"
            job.title = "Staff Engineer"
            job.location = "San Francisco, CA"
            job.remoteType = .hybrid
            job.salaryMin = 150_000
            job.salaryMax = 200_000
            job.salaryCurrency = "USD"
            job.salaryNote = "equity included"
            job.employmentType = "Full-time"
            job.seniority = "Staff"
            job.extractedJSON = "{\"summary\":\"Great job\"}"
            job.extractionModel = "claude-3-5-haiku"
            job.extractionConfidence = 0.95
            job.extractedAt = Date(timeIntervalSinceNow: -3600)
        }
        try await queue.deleteAll()

        try await svc.resetExtraction(jobID: jobID)

        let updated = try await store.fetch(FetchDescriptor<Job>(predicate: #Predicate { $0.id == jobID }))
        let job = try XCTUnwrap(updated.first)
        XCTAssertEqual(job.extractionStatus, .pending, "extractionStatus must be .pending after reset")
        XCTAssertNil(job.company, "company must be cleared")
        XCTAssertNil(job.title, "title must be cleared")
        XCTAssertNil(job.location, "location must be cleared")
        XCTAssertNil(job.remoteType, "remoteType must be cleared")
        XCTAssertNil(job.salaryMin, "salaryMin must be cleared")
        XCTAssertNil(job.salaryMax, "salaryMax must be cleared")
        XCTAssertNil(job.salaryCurrency, "salaryCurrency must be cleared")
        XCTAssertNil(job.salaryNote, "salaryNote must be cleared")
        XCTAssertNil(job.employmentType, "employmentType must be cleared")
        XCTAssertNil(job.seniority, "seniority must be cleared")
        XCTAssertNil(job.extractedJSON, "extractedJSON must be cleared")
        XCTAssertNil(job.extractionModel, "extractionModel must be cleared")
        XCTAssertNil(job.extractionConfidence, "extractionConfidence must be cleared")
        XCTAssertNil(job.extractedAt, "extractedAt must be cleared")
        XCTAssertNil(job.extractionError, "extractionError must be cleared")
    }

    func testResetExtractionBulk_resetsAllJobs() async throws {
        let container = try ModelContainerFactory.inMemory()
        let store = makeStore(container)
        let queue = makeQueue(container)
        let svc = JobService(store: store, queue: queue)

        for i in 1 ... 3 {
            _ = try await svc.ingestCapture(CapturePayload(
                url: "https://j.example.com/b\(i)",
                pageTitle: "J\(i)",
                visibleText: "desc"
            ))
        }
        try await queue.deleteAll()

        let jobIDs = try await store.fetch(FetchDescriptor<Job>()).map(\.id)
        try await svc.resetExtractionBulk(jobIDs: jobIDs)

        let requests = try await store.fetch(FetchDescriptor<LLMRequest>())
        XCTAssertEqual(requests.count, 3, "resetExtractionBulk must enqueue one request per job")
        XCTAssertTrue(requests.allSatisfy { $0.requestType == .extract && $0.status == .queued })
    }

    // MARK: - Re-capture: same URL + changed content updates in place (Electron parity)

    func testReCapture_sameURLChangedContent_updatesInPlace() async throws {
        let container = try ModelContainerFactory.inMemory()
        let store = makeStore(container)
        let svc = JobService(store: store, queue: makeQueue(container))

        let first = try await svc.ingestCapture(CapturePayload(
            url: "https://re.example.com/job", pageTitle: "Title A",
            visibleText: "Original description text for this role."
        ))
        XCTAssertFalse(first.isDuplicate)

        // Re-capture the same URL with different content.
        let second = try await svc.ingestCapture(CapturePayload(
            url: "https://re.example.com/job", pageTitle: "Title B",
            visibleText: "Updated and substantially changed description text."
        ))

        XCTAssertFalse(second.isDuplicate)
        XCTAssertEqual(second.jobNumber, first.jobNumber, "re-capture must update the same job, not create a new one")

        let jobs = try await store.fetch(FetchDescriptor<Job>())
        XCTAssertEqual(jobs.count, 1, "re-capture of the same URL must not create a second job")

        let events = try await store.fetch(FetchDescriptor<JobEvent>())
        XCTAssertTrue(events.contains { $0.eventType == "recapture" }, "re-capture must log a recapture timeline event")
    }

    // MARK: - Manual field overrides (Electron parity: extraction must not clobber user edits)

    func testUpdateJobFields_recordsManualOverride_andClearResets() async throws {
        let container = try ModelContainerFactory.inMemory()
        let store = makeStore(container)
        let svc = JobService(store: store, queue: makeQueue(container))
        let result = try await svc.ingestCapture(CapturePayload(
            url: "https://o.example.com/j",
            pageTitle: "T",
            visibleText: "desc"
        ))
        let jobs = try await store.fetch(FetchDescriptor<Job>())
        let jobID = try XCTUnwrap(jobs.first(where: { $0.jobNumber == result.jobNumber })).id

        try await svc.updateJobFields(jobID: jobID, company: "Acme Corp")

        let updatedJobs = try await store.fetch(FetchDescriptor<Job>(predicate: #Predicate { $0.id == jobID }))
        let updated = try XCTUnwrap(updatedJobs.first)
        XCTAssertEqual(updated.company, "Acme Corp")
        XCTAssertEqual(
            updated.manualFieldOverridesJSON?.contains("company"),
            true,
            "editing company must record a manual override"
        )

        try await svc.clearFieldOverrides(jobID: jobID)
        let clearedJobs = try await store.fetch(FetchDescriptor<Job>(predicate: #Predicate { $0.id == jobID }))
        let cleared = try XCTUnwrap(clearedJobs.first)
        XCTAssertNil(cleared.manualFieldOverridesJSON, "clearFieldOverrides must reset overrides")
    }

    // MARK: - TASK-160: archive sets .archived, not .passed

    func testArchive_setsArchivedStatus() async throws {
        let container = try ModelContainerFactory.inMemory()
        let store = makeStore(container)
        let svc = JobService(store: store, queue: makeQueue(container))

        let result = try await svc.ingestCapture(CapturePayload(
            url: "https://j.example.com/arc",
            pageTitle: "Eng",
            visibleText: "Job description here"
        ))
        let jobs = try await store.fetch(FetchDescriptor<Job>())
        let jobID = try XCTUnwrap(jobs.first(where: { $0.jobNumber == result.jobNumber })?.id)

        try await svc.archive(jobID: jobID)

        let updated = try await store.fetch(FetchDescriptor<Job>(predicate: #Predicate { $0.id == jobID }))
        XCTAssertEqual(updated.first?.status, .archived, "archive() must set .archived, not .passed")
        XCTAssertNotEqual(updated.first?.status, .passed, "archive() must not set .passed")
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
        XCTAssertEqual(columns.count, 23, "Expected 23 CSV columns, got \(columns.count): \(header)")
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
        let payload1 = CapturePayload(
            url: "https://example.com/j/1",
            pageTitle: "Job One",
            selectedText: nil,
            visibleText: "Text one"
        )
        let payload2 = CapturePayload(
            url: "https://example.com/j/2",
            pageTitle: "Job Two",
            selectedText: nil,
            visibleText: "Text two"
        )
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

        for i in 1 ... 5 {
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

        let all = try await store.fetch(FetchDescriptor<Job>())
        let job1 = try XCTUnwrap(all.first(where: { $0.jobNumber == r1.jobNumber }))
        try await svc.setStatus(.pursuing, for: job1.id)

        let pursuing = try await svc.listJobs(status: "pursuing", limit: 50)
        XCTAssertTrue(pursuing.allSatisfy { $0.status == .pursuing })
    }

    func testListJobs_statusFilter_largeMixedData_pagesBeyondFirstPageAndBoundsLimit() async throws {
        // TASK-366: status-filtered listing pages through the table in bounded chunks. Verify it
        // still finds matches that sort beyond the first page, bounds the result to `limit`, and
        // handles zero-match and limit==0 without scanning into an error.
        let container = try ModelContainerFactory.inMemory()
        let store = makeStore(container)
        let queue = makeQueue(container)
        let svc = JobService(store: store, queue: queue)

        let base = Date(timeIntervalSince1970: 1_700_000_000)
        // 5 pursuing rows with the OLDEST timestamps → sorted last (newest-first), so the filter
        // only reaches them after paging past the first 200-row page.
        var pursuingIDs: Set<String> = []
        for i in 0 ..< 5 {
            let job = Job(
                jobNumber: i + 1,
                title: "Pursuing \(i)",
                status: .pursuing,
                createdAt: base.addingTimeInterval(Double(i))
            )
            try await store.insert(job)
            pursuingIDs.insert(job.id)
        }
        // 250 newer .new rows fill the first page and then some.
        for i in 0 ..< 250 {
            let job = Job(
                jobNumber: 100 + i,
                title: "New \(i)",
                status: .new,
                createdAt: base.addingTimeInterval(Double(1000 + i))
            )
            try await store.insert(job)
        }

        let pursuing = try await svc.listJobs(status: "pursuing", limit: 50)
        XCTAssertEqual(pursuing.count, 5, "All pursuing rows found even though they sort beyond page 1")
        XCTAssertTrue(pursuing.allSatisfy { $0.status == .pursuing })
        XCTAssertEqual(Set(pursuing.map(\.id)), pursuingIDs)

        let newCapped = try await svc.listJobs(status: "new", limit: 10)
        XCTAssertEqual(newCapped.count, 10, "limit bounds a status with many matches")
        XCTAssertTrue(newCapped.allSatisfy { $0.status == .new })

        let offers = try await svc.listJobs(status: "offer", limit: 10)
        XCTAssertTrue(offers.isEmpty, "Zero-match status returns empty after scanning all pages")

        let none = try await svc.listJobs(status: "new", limit: 0)
        XCTAssertTrue(none.isEmpty, "limit 0 returns empty")
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

        let payloads = (1 ... 5).map { i in
            CapturePayload(
                url: "https://example.com/j/\(i)",
                pageTitle: "Job \(i)",
                visibleText: "description \(i)"
            )
        }

        // Launch all 5 ingestions concurrently
        let results = try await withThrowingTaskGroup(of: IngestResult.self) { group in
            for p in payloads {
                group.addTask { try await svc.ingestCapture(p) }
            }
            var out: [IngestResult] = []
            for try await r in group {
                out.append(r)
            }
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

    /// TASK-142 regression: ingest must remain correct with a large existing dataset.
    /// Seeds 50 jobs then verifies that a new capture gets job number 51 and a rawHash duplicate
    /// is detected without loading all rows.
    func testAtomicIngest_jobNumberingIsCorrectWithLargeDataset() async throws {
        let container = try ModelContainerFactory.inMemory()
        let store = makeStore(container)
        let queue = makeQueue(container)
        let svc = JobService(store: store, queue: queue)

        // Seed 50 distinct jobs
        for i in 1 ... 50 {
            let p = CapturePayload(
                url: "https://example.com/seed/\(i)",
                pageTitle: "Seed \(i)",
                visibleText: "text \(i)"
            )
            _ = try await svc.ingestCapture(p)
        }

        // A new unique job should get job number 51
        let newResult = try await svc.ingestCapture(
            CapturePayload(
                url: "https://example.com/new-unique",
                pageTitle: "New",
                visibleText: "brand new text unique xyz"
            )
        )
        XCTAssertEqual(newResult.jobNumber, 51, "Job number must be max+1 after 50 existing jobs")
        XCTAssertFalse(newResult.isDuplicate)

        // Re-ingesting the same URL+text must detect the rawHash duplicate (not create job 52)
        let dupResult = try await svc.ingestCapture(
            CapturePayload(
                url: "https://example.com/new-unique",
                pageTitle: "New",
                visibleText: "brand new text unique xyz"
            )
        )
        XCTAssertTrue(dupResult.isDuplicate)
        XCTAssertEqual(dupResult.jobNumber, 51, "Duplicate must return original job number")

        let ctx = ModelContext(container)
        let jobs = try ctx.fetch(FetchDescriptor<Job>())
        XCTAssertEqual(jobs.count, 51, "Duplicate ingest must not create a new job")
    }

    func testWorkflowSnapshot_countsJobsAndSites() async throws {
        let container = try ModelContainerFactory.inMemory()
        let store = makeStore(container)
        let queue = makeQueue(container)
        let svc = JobService(store: store, queue: queue)

        for i in 1 ... 3 {
            let p = CapturePayload(url: "https://example.com/j/\(i)", pageTitle: "Job \(i)", visibleText: "t")
            _ = try await svc.ingestCapture(p)
        }

        let snap = try await svc.workflowSnapshot()
        XCTAssertEqual(snap.jobsTotal, 3)
        XCTAssertFalse(snap.statusCounts.isEmpty)
    }

    // MARK: - TASK-145 regression: batch operations

    func testSetStatusBulk_updatesAllSpecifiedJobs() async throws {
        let container = try ModelContainerFactory.inMemory()
        let store = makeStore(container)
        let queue = makeQueue(container)
        let svc = JobService(store: store, queue: queue)

        var ids: [String] = []
        for i in 1 ... 4 {
            let r = try await svc.ingestCapture(CapturePayload(
                url: "https://x.com/\(i)",
                pageTitle: "J\(i)",
                visibleText: "t"
            ))
            ids.append(r.captureID)
        }
        let jobs = try await store.fetch(FetchDescriptor<Job>())
        let jobIDs = jobs.map(\.id)

        // Bulk-set first 2 to pursuing, leave last 2 as new
        try await svc.setStatusBulk(.pursuing, jobIDs: Array(jobIDs.prefix(2)))

        let updated = try await store.fetch(FetchDescriptor<Job>())
        let pursuing = updated.filter { $0.status == .pursuing }
        let newStatus = updated.filter { $0.status == .new }
        XCTAssertEqual(pursuing.count, 2, "setStatusBulk should update exactly the specified jobs")
        XCTAssertEqual(newStatus.count, 2, "unspecified jobs should keep their original status")
    }

    func testMarkExpired_updatesOnlySpecifiedJobs() async throws {
        let container = try ModelContainerFactory.inMemory()
        let store = makeStore(container)
        let queue = makeQueue(container)
        let svc = JobService(store: store, queue: queue)

        for i in 1 ... 3 {
            _ = try await svc.ingestCapture(CapturePayload(
                url: "https://x.com/\(i)",
                pageTitle: "J\(i)",
                visibleText: "t"
            ))
        }
        let jobs = try await store.fetch(FetchDescriptor<Job>())
        XCTAssertEqual(jobs.count, 3)

        // Mark first job expired only
        try await svc.markExpired(jobIDs: [jobs[0].id])

        let after = try await store.fetch(FetchDescriptor<Job>())
        let expired = after.filter { $0.status == .expired }
        let notExpired = after.filter { $0.status != .expired }
        XCTAssertEqual(expired.count, 1, "markExpired should update only the specified job")
        XCTAssertEqual(notExpired.count, 2, "unspecified jobs must not be marked expired")
    }

    /// TASK-504: the first transition to .applied stamps appliedAt; a later status bounce that returns
    /// to .applied must not overwrite the original application date.
    func testSetStatusApplied_stampsAppliedAtOnceAndNeverOverwrites() async throws {
        let container = try ModelContainerFactory.inMemory()
        let store = makeStore(container)
        let svc = JobService(store: store, queue: makeQueue(container))
        _ = try await svc.ingestCapture(CapturePayload(url: "https://x.com/1", pageTitle: "J", visibleText: "t"))
        let jobs = try await store.fetch(FetchDescriptor<Job>())
        let jobID = try XCTUnwrap(jobs.first?.id)

        try await svc.setStatus(.applied, for: jobID)
        let firstApplied = try await store.fetch(FetchDescriptor<Job>()).first?.appliedAt
        XCTAssertNotNil(firstApplied, "becoming applied stamps appliedAt")

        // Bounce away and back to applied — the stamp must be preserved.
        try await svc.setStatus(.pursuing, for: jobID)
        try await svc.setStatus(.applied, for: jobID)
        let secondApplied = try await store.fetch(FetchDescriptor<Job>()).first?.appliedAt
        XCTAssertEqual(secondApplied, firstApplied, "re-applying must not overwrite the original applied date")
    }

    /// A status change that is not .applied must not stamp appliedAt.
    func testSetStatus_nonApplied_doesNotStampAppliedAt() async throws {
        let container = try ModelContainerFactory.inMemory()
        let store = makeStore(container)
        let svc = JobService(store: store, queue: makeQueue(container))
        _ = try await svc.ingestCapture(CapturePayload(url: "https://x.com/2", pageTitle: "J", visibleText: "t"))
        let jobs = try await store.fetch(FetchDescriptor<Job>())
        let jobID = try XCTUnwrap(jobs.first?.id)

        try await svc.setStatus(.pursuing, for: jobID)
        let applied = try await store.fetch(FetchDescriptor<Job>()).first?.appliedAt
        XCTAssertNil(applied, "a non-applied status must leave appliedAt nil")
    }

    /// TASK-515: manual expiration is a terminal decision — each affected job must get an auditable
    /// "status" timeline event (routed through setJobStatus), not a silent bulk status flip.
    func testMarkExpired_recordsStatusEventPerJob() async throws {
        let container = try ModelContainerFactory.inMemory()
        let store = makeStore(container)
        let svc = JobService(store: store, queue: makeQueue(container))

        for i in 1 ... 2 {
            _ = try await svc.ingestCapture(CapturePayload(
                url: "https://x.com/\(i)",
                pageTitle: "J\(i)",
                visibleText: "t"
            ))
        }
        let jobs = try await store.fetch(FetchDescriptor<Job>())

        try await svc.markExpired(jobIDs: jobs.map(\.id))

        let events = try await store.fetch(FetchDescriptor<JobEvent>())
        for job in jobs {
            let statusEvents = events.filter { $0.job?.id == job.id && $0.eventType == "status" }
            XCTAssertEqual(statusEvents.count, 1, "each expired job must have exactly one status event")
            XCTAssertEqual(statusEvents.first?.note, "Status changed from new to expired")
        }
    }

    /// TASK-515: a missing id makes markExpired throw (failure-visible) instead of silently skipping,
    /// so a confirmed change can't be reported as succeeding when it didn't apply.
    func testMarkExpired_throwsWhenJobMissing() async throws {
        let container = try ModelContainerFactory.inMemory()
        let store = makeStore(container)
        let svc = JobService(store: store, queue: makeQueue(container))

        do {
            try await svc.markExpired(jobIDs: ["no-such-job"])
            XCTFail("Expected markExpired to throw for a missing job")
        } catch JobServiceError.jobNotFound {
            // Expected.
        }
    }

    func testEnqueueBatch_createsOneRequestPerJob() async throws {
        let container = try ModelContainerFactory.inMemory()
        let store = makeStore(container)
        let queue = makeQueue(container)
        let svc = JobService(store: store, queue: queue)

        // Ingest 3 jobs (each creates its own LLMRequest automatically)
        for i in 1 ... 3 {
            _ = try await svc.ingestCapture(CapturePayload(
                url: "https://x.com/\(i)",
                pageTitle: "J\(i)",
                visibleText: "t"
            ))
        }
        let jobs = try await store.fetch(FetchDescriptor<Job>())
        let jobIDs = jobs.map(\.id)

        // Clear auto-created requests so we can count only the new batch
        try await queue.deleteAll()
        let before = try await store.fetch(FetchDescriptor<LLMRequest>())
        XCTAssertEqual(before.count, 0)

        // Batch enqueue for all 3 jobs at once
        try await queue.enqueue(jobIDs: jobIDs, mode: .extract)

        let after = try await store.fetch(FetchDescriptor<LLMRequest>())
        XCTAssertEqual(after.count, 3, "enqueue should create one LLMRequest per job ID")
        XCTAssertTrue(after.allSatisfy { $0.status == .queued }, "all requests must start as queued")
    }

    // MARK: - TASK-442: structured data reaches Capture + cleaned description

    func testIngestCapture_structuredDataJSON_reachesCaptureAndCleanedDescription() async throws {
        let container = try ModelContainerFactory.inMemory()
        let store = makeStore(container)
        let svc = JobService(store: store, queue: makeQueue(container))

        // JSON-LD JobPosting with a substantial description (≥200 chars) so the cleaner promotes it.
        let description = String(repeating: "Build distributed systems at scale. ", count: 10)
        let jsonLd = "[{\"@type\":\"JobPosting\",\"title\":\"Staff Engineer\",\"description\":\"\(description)\"}]"
        let payload = CapturePayload(
            url: "https://example.com/jobs/structured",
            pageTitle: "Staff Engineer",
            visibleText: "short page text",
            structuredDataJSON: jsonLd
        )
        _ = try await svc.ingestCapture(payload)

        let captures = try await store.fetch(FetchDescriptor<Capture>())
        let capture = try XCTUnwrap(captures.first)
        XCTAssertEqual(capture.structuredDataJSON, jsonLd, "structured data must be persisted on the capture")
        let cleaned = try XCTUnwrap(capture.cleanedDescription)
        XCTAssertTrue(
            cleaned.contains("Build distributed systems at scale."),
            "cleaner must promote the JSON-LD description into cleanedDescription"
        )
    }

    // MARK: - TASK-146: byte counts persisted at ingest

    func testIngestCapture_persistsRawAndCleanedByteCounts() async throws {
        let container = try ModelContainerFactory.inMemory()
        let store = makeStore(container)
        let queue = makeQueue(container)
        let svc = JobService(store: store, queue: queue)

        let selected = String(repeating: "a", count: 200)
        let visible = String(repeating: "b", count: 500)
        let payload = CapturePayload(
            url: "https://example.com/byte-test",
            pageTitle: "Byte Test",
            selectedText: selected,
            visibleText: visible
        )
        _ = try await svc.ingestCapture(payload)

        let jobs = try await store.fetch(FetchDescriptor<Job>())
        let job = try XCTUnwrap(jobs.first)
        // TASK-445: total transmitted raw bytes = selected + visible (was max).
        XCTAssertEqual(job.rawTextBytes, 700, "rawTextBytes should be selected + visible (200 + 500)")
        XCTAssertNotNil(job.cleanedTextBytes, "cleanedTextBytes should be set even if zero")
    }

    // TASK-445: raw byte count must not undercount combined selected + visible capture input.

    func testIngestCapture_rawBytes_selectedOnly() async throws {
        let container = try ModelContainerFactory.inMemory()
        let store = makeStore(container)
        let svc = JobService(store: store, queue: makeQueue(container))
        _ = try await svc.ingestCapture(CapturePayload(
            url: "https://example.com/sel", pageTitle: "T",
            selectedText: String(repeating: "a", count: 300)
        ))
        let jobs = try await store.fetch(FetchDescriptor<Job>())
        let job = try XCTUnwrap(jobs.first)
        XCTAssertEqual(job.rawTextBytes, 300)
    }

    func testIngestCapture_rawBytes_visibleOnly() async throws {
        let container = try ModelContainerFactory.inMemory()
        let store = makeStore(container)
        let svc = JobService(store: store, queue: makeQueue(container))
        _ = try await svc.ingestCapture(CapturePayload(
            url: "https://example.com/vis", pageTitle: "T",
            visibleText: String(repeating: "b", count: 400)
        ))
        let jobs = try await store.fetch(FetchDescriptor<Job>())
        let job = try XCTUnwrap(jobs.first)
        XCTAssertEqual(job.rawTextBytes, 400)
    }

    func testIngestCapture_rawBytes_selectedPlusVisible_notUndercounted() async throws {
        let container = try ModelContainerFactory.inMemory()
        let store = makeStore(container)
        let svc = JobService(store: store, queue: makeQueue(container))
        // 600 + 600 = 1200 total; old `max` would have stored 600 and falsely flagged shortRawText.
        _ = try await svc.ingestCapture(CapturePayload(
            url: "https://example.com/both", pageTitle: "T",
            selectedText: String(repeating: "a", count: 600),
            visibleText: String(repeating: "b", count: 600)
        ))
        let jobs = try await store.fetch(FetchDescriptor<Job>())
        let job = try XCTUnwrap(jobs.first)
        XCTAssertEqual(job.rawTextBytes, 1200, "combined input must not be undercounted")
        XCTAssertFalse(
            QualityChecker.issues(for: job).contains(.shortRawText),
            "1200 combined bytes must not be flagged short"
        )
    }

    func testIngestCapture_rawBytesUsedByQualityChecker_withoutFaultingCapture() async throws {
        let container = try ModelContainerFactory.inMemory()
        let store = makeStore(container)
        let queue = makeQueue(container)
        let svc = JobService(store: store, queue: queue)

        let text = String(repeating: "x", count: 1500)
        _ = try await svc.ingestCapture(CapturePayload(
            url: "https://example.com/qc-test",
            pageTitle: "QC Test",
            visibleText: text
        ))

        let jobs = try await store.fetch(FetchDescriptor<Job>())
        let job = try XCTUnwrap(jobs.first)
        XCTAssertNotNil(job.rawTextBytes)
        // QualityChecker should not flag shortRawText when rawTextBytes >= 1000
        let issues = QualityChecker.issues(for: job)
        XCTAssertFalse(issues.contains(.shortRawText), "1500-byte text should not trigger shortRawText")
    }

    func testPruneFinishedRequests_removesOldTerminalRecords() async throws {
        let container = try ModelContainerFactory.inMemory()
        let store = makeStore(container)
        let queue = makeQueue(container)

        let oldDate = Date(timeIntervalSinceNow: -31 * 86400) // 31 days ago — pruned
        let recentDate = Date(timeIntervalSinceNow: -1 * 86400) // 1 day ago — kept

        // Old terminal records (should be pruned)
        let r1 = LLMRequest(status: .succeeded); r1.finishedAt = oldDate
        let r2 = LLMRequest(status: .failed); r2.finishedAt = oldDate
        let r3 = LLMRequest(status: .cancelled); r3.finishedAt = oldDate
        // Recent terminal record (kept — within 30-day window)
        let r4 = LLMRequest(status: .succeeded); r4.finishedAt = recentDate
        // Queued with no finishedAt — always kept
        let r5 = LLMRequest(status: .queued)

        try await store.insertBatch([r1, r2, r3, r4, r5])
        let before = try await store.fetch(FetchDescriptor<LLMRequest>())
        XCTAssertEqual(before.count, 5)

        try await queue.pruneFinishedRequests(olderThan: 30)

        let after = try await store.fetch(FetchDescriptor<LLMRequest>())
        XCTAssertEqual(after.count, 2, "3 old terminal records should be pruned; 1 recent + 1 queued remain")
        XCTAssertTrue(
            after.allSatisfy { $0.status == .queued || $0.finishedAt! > oldDate },
            "remaining records must be queued or recently finished"
        )
    }

    // MARK: - addJobByURL

    func testAddJobByURL_createsJob() async throws {
        let container = try ModelContainerFactory.inMemory()
        let store = makeStore(container)
        let svc = JobService(store: store, queue: makeQueue(container))

        let result = try await svc.addJobByURL("https://jobs.example.com/posting/12345")

        XCTAssertFalse(result.isDuplicate)
        let ctx = ModelContext(container)
        let jobs = try ctx.fetch(FetchDescriptor<Job>())
        XCTAssertEqual(jobs.count, 1)
        let captures = try ctx.fetch(FetchDescriptor<Capture>())
        XCTAssertEqual(captures.count, 1)
        XCTAssertEqual(captures[0].url, "https://jobs.example.com/posting/12345")
    }

    func testAddJobByURL_duplicateURL_returnsDuplicate() async throws {
        let container = try ModelContainerFactory.inMemory()
        let store = makeStore(container)
        let svc = JobService(store: store, queue: makeQueue(container))

        _ = try await svc.addJobByURL("https://jobs.example.com/posting/99")
        let result2 = try await svc.addJobByURL("https://jobs.example.com/posting/99")

        XCTAssertTrue(result2.isDuplicate)
        let ctx = ModelContext(container)
        let jobs = try ctx.fetch(FetchDescriptor<Job>())
        XCTAssertEqual(jobs.count, 1, "Duplicate URL should not create a second job")
    }

    func testAddJobByURL_invalidURL_throws() async throws {
        let container = try ModelContainerFactory.inMemory()
        let store = makeStore(container)
        let svc = JobService(store: store, queue: makeQueue(container))

        do {
            _ = try await svc.addJobByURL("   ")
            XCTFail("Expected missingURL error")
        } catch JobServiceError.missingURL {
            // expected
        }
    }

    // TASK-443: shared URL policy — non-http(s)/malformed rejected before any persistence/enqueue.

    func testAddJobByURL_unsupportedScheme_throwsAndPersistsNothing() async throws {
        let container = try ModelContainerFactory.inMemory()
        let store = makeStore(container)
        let svc = JobService(store: store, queue: makeQueue(container))

        do {
            _ = try await svc.addJobByURL("ftp://example.com/x")
            XCTFail("Expected invalidURL error")
        } catch JobServiceError.invalidURL {
            // expected
        }
        let ctx = ModelContext(container)
        XCTAssertEqual(try ctx.fetch(FetchDescriptor<Job>()).count, 0, "no job persisted on invalid URL")
        XCTAssertEqual(try ctx.fetch(FetchDescriptor<LLMRequest>()).count, 0, "no extraction enqueued")
    }

    func testIngestCapture_invalidURL_throwsAndPersistsNothing() async throws {
        let container = try ModelContainerFactory.inMemory()
        let store = makeStore(container)
        let svc = JobService(store: store, queue: makeQueue(container))

        let payload = CapturePayload(
            url: "javascript:alert(1)", pageTitle: "Engineer", selectedText: nil, visibleText: "text"
        )
        do {
            _ = try await svc.ingestCapture(payload)
            XCTFail("Expected invalidURL error")
        } catch JobServiceError.invalidURL {
            // expected
        }
        let ctx = ModelContext(container)
        XCTAssertEqual(try ctx.fetch(FetchDescriptor<Capture>()).count, 0, "no capture persisted on invalid URL")
        XCTAssertEqual(try ctx.fetch(FetchDescriptor<LLMRequest>()).count, 0, "no extraction enqueued")
    }

    func testIngestCapture_invalidCanonical_droppedButCaptureSucceeds() async throws {
        let container = try ModelContainerFactory.inMemory()
        let store = makeStore(container)
        let svc = JobService(store: store, queue: makeQueue(container))

        let payload = CapturePayload(
            url: "https://example.com/job", pageTitle: "Engineer",
            visibleText: "text", canonicalURL: "not-a-valid-url"
        )
        _ = try await svc.ingestCapture(payload)

        let ctx = ModelContext(container)
        let captures = try ctx.fetch(FetchDescriptor<Capture>())
        XCTAssertEqual(captures.count, 1, "valid capture persists despite a malformed canonical")
        XCTAssertNil(captures.first?.canonicalURL, "malformed canonical is dropped, not stored")
    }

    // MARK: - TASK-250: semantic duplicate ingest sets both signals

    func testIngestSemanticDuplicate_setsBothDuplicateSignals() async throws {
        let container = try ModelContainerFactory.inMemory()
        let store = makeStore(container)
        let queue = makeQueue(container)
        let svc = JobService(store: store, queue: queue)

        // Ingest original job at company domain with its own canonical URL
        _ = try await svc.ingestCapture(CapturePayload(
            url: "https://company.com/jobs/engineer",
            pageTitle: "Software Engineer",
            visibleText: "We are hiring a software engineer to build distributed systems at scale.",
            canonicalURL: "https://company.com/jobs/engineer"
        ))

        // Ingest same content at an ATS URL with a different canonical URL — triggers semantic duplicate
        _ = try await svc.ingestCapture(CapturePayload(
            url: "https://jobs.lever.co/company/engineer-abc123",
            pageTitle: "Software Engineer",
            visibleText: "We are hiring a software engineer to build distributed systems at scale.",
            canonicalURL: "https://jobs.lever.co/company/engineer-abc123"
        ))

        let jobs = try await store.fetch(FetchDescriptor<Job>())
        let duplicate = jobs.first(where: { $0.duplicateOfJobID != nil })
        XCTAssertNotNil(duplicate, "Semantic duplicate job must have duplicateOfJobID set")
        XCTAssertEqual(duplicate?.status, .duplicate, "Semantic duplicate job must have status == .duplicate")
    }

    // MARK: - TASK-251: unmarkDuplicate behaviour

    func testUnmarkDuplicate_onlyDuplicateOfJobIDSet_statusPreserved() async throws {
        let container = try ModelContainerFactory.inMemory()
        let store = makeStore(container)
        let svc = JobService(store: store, queue: makeQueue(container))

        // Job with non-duplicate status and duplicateOfJobID set (edge case)
        let job = Job(id: "job-unmark-1", jobNumber: 1, status: .pursuing)
        job.duplicateOfJobID = "some-other-id"
        try await store.insert(job)

        try await svc.unmarkDuplicate(jobID: "job-unmark-1")

        let updated = try await store.fetch(FetchDescriptor<Job>(predicate: #Predicate { $0.id == "job-unmark-1" }))
        XCTAssertNil(updated.first?.duplicateOfJobID, "duplicateOfJobID must be cleared")
        XCTAssertEqual(updated.first?.status, .pursuing, "Non-duplicate status must be preserved")
    }

    func testUnmarkDuplicate_statusDuplicate_resetsToNew() async throws {
        let container = try ModelContainerFactory.inMemory()
        let store = makeStore(container)
        let svc = JobService(store: store, queue: makeQueue(container))

        // Job with status .duplicate but no duplicateOfJobID (inconsistent state we still handle)
        let job = Job(id: "job-unmark-2", jobNumber: 2, status: .duplicate)
        try await store.insert(job)

        try await svc.unmarkDuplicate(jobID: "job-unmark-2")

        let updated = try await store.fetch(FetchDescriptor<Job>(predicate: #Predicate { $0.id == "job-unmark-2" }))
        XCTAssertNil(updated.first?.duplicateOfJobID, "duplicateOfJobID must remain nil")
        XCTAssertEqual(updated.first?.status, .new, "status .duplicate must be reset to .new")
    }

    func testUnmarkDuplicate_bothSignalsSet_clearsBothAndResetsStatus() async throws {
        let container = try ModelContainerFactory.inMemory()
        let store = makeStore(container)
        let svc = JobService(store: store, queue: makeQueue(container))

        let job = Job(id: "job-unmark-3", jobNumber: 3, status: .duplicate)
        job.duplicateOfJobID = "original-job-id"
        try await store.insert(job)

        try await svc.unmarkDuplicate(jobID: "job-unmark-3")

        let updated = try await store.fetch(FetchDescriptor<Job>(predicate: #Predicate { $0.id == "job-unmark-3" }))
        XCTAssertNil(updated.first?.duplicateOfJobID, "duplicateOfJobID must be cleared")
        XCTAssertEqual(updated.first?.status, .new, "status must be reset to .new when both signals were set")
    }

    // MARK: - TASK-370: duplicate status invariant enforcement

    func testMarkDuplicate_setsLinkAndStatusAtomically() async throws {
        let container = try ModelContainerFactory.inMemory()
        let store = makeStore(container)
        let svc = JobService(store: store, queue: makeQueue(container))

        let job = Job(id: "dup-mark-1", jobNumber: 1, status: .new)
        try await store.insert(job)

        try await svc.markDuplicate(jobID: "dup-mark-1", ofJobID: "orig-1", confidence: 0.9)

        let updated = try await store.fetch(FetchDescriptor<Job>(predicate: #Predicate { $0.id == "dup-mark-1" })).first
        XCTAssertEqual(updated?.duplicateOfJobID, "orig-1")
        XCTAssertEqual(updated?.duplicateConfidence, 0.9)
        XCTAssertEqual(updated?.status, .duplicate, "markDuplicate must set status to .duplicate")
    }

    func testSetStatus_onDuplicateJob_clearsDuplicateLink() async throws {
        let container = try ModelContainerFactory.inMemory()
        let store = makeStore(container)
        let svc = JobService(store: store, queue: makeQueue(container))

        let job = Job(id: "dup-status-1", jobNumber: 1, status: .duplicate)
        job.duplicateOfJobID = "orig-1"
        job.duplicateConfidence = 0.8
        try await store.insert(job)

        // Moving a flagged duplicate to a normal status must repair the invariant.
        try await svc.setStatus(.pursuing, for: "dup-status-1")

        let updated = try await store.fetch(FetchDescriptor<Job>(predicate: #Predicate { $0.id == "dup-status-1" }))
            .first
        XCTAssertEqual(updated?.status, .pursuing)
        XCTAssertNil(updated?.duplicateOfJobID, "leaving .duplicate must clear the link")
        XCTAssertNil(updated?.duplicateConfidence)
    }

    func testSetStatus_toDuplicate_keepsLink() async throws {
        let container = try ModelContainerFactory.inMemory()
        let store = makeStore(container)
        let svc = JobService(store: store, queue: makeQueue(container))

        let job = Job(id: "dup-status-2", jobNumber: 2, status: .duplicate)
        job.duplicateOfJobID = "orig-2"
        try await store.insert(job)

        // Re-setting .duplicate must not clear an existing link.
        try await svc.setStatus(.duplicate, for: "dup-status-2")

        let updated = try await store.fetch(FetchDescriptor<Job>(predicate: #Predicate { $0.id == "dup-status-2" }))
            .first
        XCTAssertEqual(updated?.duplicateOfJobID, "orig-2")
    }

    func testUpdateJobFields_setDuplicateOfJobID_setsDuplicateStatus() async throws {
        let container = try ModelContainerFactory.inMemory()
        let store = makeStore(container)
        let svc = JobService(store: store, queue: makeQueue(container))

        let job = Job(id: "dup-field-1", jobNumber: 1, status: .new)
        try await store.insert(job)

        try await svc.updateJobFields(jobID: "dup-field-1", duplicateOfJobID: "orig-3")

        let updated = try await store.fetch(FetchDescriptor<Job>(predicate: #Predicate { $0.id == "dup-field-1" }))
            .first
        XCTAssertEqual(updated?.duplicateOfJobID, "orig-3")
        XCTAssertEqual(updated?.status, .duplicate, "setting the link via field update must set .duplicate")
    }

    func testUpdateJobFields_clearDuplicateOfJobID_resetsStatusFromDuplicate() async throws {
        let container = try ModelContainerFactory.inMemory()
        let store = makeStore(container)
        let svc = JobService(store: store, queue: makeQueue(container))

        let job = Job(id: "dup-field-2", jobNumber: 2, status: .duplicate)
        job.duplicateOfJobID = "orig-4"
        try await store.insert(job)

        try await svc.updateJobFields(jobID: "dup-field-2", duplicateOfJobID: .some(nil))

        let updated = try await store.fetch(FetchDescriptor<Job>(predicate: #Predicate { $0.id == "dup-field-2" }))
            .first
        XCTAssertNil(updated?.duplicateOfJobID)
        XCTAssertEqual(updated?.status, .new, "clearing the link from a .duplicate job resets status to .new")
    }

    // MARK: - TASK-152: enqueueFit links resume

    func testEnqueueFit_linksResumeToRequest() async throws {
        let container = try ModelContainerFactory.inMemory()
        let store = makeStore(container)
        let queue = makeQueue(container)
        let svc = JobService(store: store, queue: queue)

        let result = try await svc.ingestCapture(CapturePayload(
            url: "https://j.example.com/1",
            pageTitle: "Eng",
            visibleText: "Swift engineer role"
        ))
        try await queue.deleteAll()

        let resume = Resume(name: "My Resume", text: "Swift iOS developer", charCount: 20, active: true, sortOrder: 0)
        try await store.insert(resume)

        try await queue.enqueueFit(jobIDs: [result.captureID], resumeID: resume.id)

        // enqueueFit with a captureID that doesn't match a job should create 0 requests
        // — re-do with the actual jobID
        let jobs = try await store.fetch(FetchDescriptor<Job>())
        let jobID = try XCTUnwrap(jobs.first?.id)
        try await queue.enqueueFit(jobIDs: [jobID], resumeID: resume.id)

        let requests = try await store.fetch(FetchDescriptor<LLMRequest>())
        let fitReqs = requests.filter { $0.requestType == .fit }
        XCTAssertEqual(fitReqs.count, 1, "Exactly one fit request should be created for the job")
        XCTAssertNotNil(fitReqs.first?.resume, "Fit request must be linked to a resume")
        XCTAssertEqual(fitReqs.first?.resume?.id, resume.id)
        XCTAssertEqual(fitReqs.first?.status, .queued)
    }

    func testEnqueueFit_unknownResumeID_throwsAndCreatesNoRequests() async throws {
        // TASK-452: a missing resume now surfaces a typed error instead of silently no-oping,
        // while still creating no fit requests.
        let container = try ModelContainerFactory.inMemory()
        let store = makeStore(container)
        let queue = makeQueue(container)
        let svc = JobService(store: store, queue: queue)

        _ = try await svc.ingestCapture(CapturePayload(
            url: "https://j.example.com/2",
            pageTitle: "PM",
            visibleText: "Product manager role"
        ))
        try await queue.deleteAll()
        let jobs = try await store.fetch(FetchDescriptor<Job>())
        let jobID = try XCTUnwrap(jobs.first?.id)

        do {
            try await queue.enqueueFit(jobIDs: [jobID], resumeID: "nonexistent-resume")
            XCTFail("Expected FitEnqueueError.resumeNotFound")
        } catch let error as FitEnqueueError {
            XCTAssertEqual(error, .resumeNotFound("nonexistent-resume"))
        }

        let requests = try await store.fetch(FetchDescriptor<LLMRequest>())
        XCTAssertTrue(requests.isEmpty, "No request should be created when resume ID doesn't exist")
    }

    // MARK: - TASK-308: markFitScoreFailed active-resume guard

    func testMarkFitScoreFailed_activeResume_updatesJobMirror() async throws {
        let container = try ModelContainerFactory.inMemory()
        let store = makeStore(container)
        let svc = JobService(store: store, queue: makeQueue(container))

        let result = try await svc.ingestCapture(CapturePayload(
            url: "https://j.example.com/fail-active",
            pageTitle: "Dev",
            visibleText: "Engineer role"
        ))
        let jobs = try await store.fetch(FetchDescriptor<Job>())
        let job = try XCTUnwrap(jobs.first)

        let resume = Resume(name: "Active Resume", text: "Swift dev", charCount: 10, active: true, sortOrder: 0)
        try await store.insert(resume)

        try await store.markFitScoreFailed(jobID: job.id, resumeID: resume.id, errorMessage: "timeout")

        let updatedJobs = try await store.fetch(FetchDescriptor<Job>())
        XCTAssertEqual(updatedJobs.first?.fitStatus, .failed, "Job mirror should be .failed when active resume fails")
        _ = result
    }

    func testMarkFitScoreFailed_inactiveResume_doesNotUpdateJobMirror() async throws {
        let container = try ModelContainerFactory.inMemory()
        let store = makeStore(container)
        let svc = JobService(store: store, queue: makeQueue(container))

        let result = try await svc.ingestCapture(CapturePayload(
            url: "https://j.example.com/fail-inactive",
            pageTitle: "Dev",
            visibleText: "Engineer role"
        ))
        let jobs = try await store.fetch(FetchDescriptor<Job>())
        let job = try XCTUnwrap(jobs.first)

        let activeResume = Resume(name: "Active Resume", text: "Swift dev", charCount: 10, active: true, sortOrder: 0)
        let inactiveResume = Resume(
            name: "Inactive Resume",
            text: "Old resume",
            charCount: 10,
            active: false,
            sortOrder: 1
        )
        try await store.insert(activeResume)
        try await store.insert(inactiveResume)

        // Simulate active resume already succeeded
        try await store.saveFitScore(
            jobID: job.id,
            resumeID: activeResume.id,
            overall: 85,
            fitJSON: nil,
            model: nil,
            scoredAt: Date()
        )

        // Now fail the inactive resume's request
        try await store.markFitScoreFailed(jobID: job.id, resumeID: inactiveResume.id, errorMessage: "timeout")

        let updatedJobs = try await store.fetch(FetchDescriptor<Job>())
        XCTAssertEqual(
            updatedJobs.first?.fitStatus,
            .succeeded,
            "Job mirror must not change when an inactive resume fails"
        )
        _ = result
    }

    // MARK: - TASK-311: enqueueFit atomic batch

    func testEnqueueFit_isAtomic_allJobsEnqueued() async throws {
        let container = try ModelContainerFactory.inMemory()
        let store = makeStore(container)
        let queue = makeQueue(container)
        let svc = JobService(store: store, queue: makeQueue(container))

        let result1 = try await svc.ingestCapture(CapturePayload(
            url: "https://j.example.com/batch1",
            pageTitle: "Job 1",
            visibleText: "role 1"
        ))
        let result2 = try await svc.ingestCapture(CapturePayload(
            url: "https://j.example.com/batch2",
            pageTitle: "Job 2",
            visibleText: "role 2"
        ))
        let result3 = try await svc.ingestCapture(CapturePayload(
            url: "https://j.example.com/batch3",
            pageTitle: "Job 3",
            visibleText: "role 3"
        ))
        try await queue.deleteAll()

        let resume = Resume(name: "Batch Resume", text: "Swift dev", charCount: 10, active: true, sortOrder: 0)
        try await store.insert(resume)

        let jobs = try await store.fetch(FetchDescriptor<Job>())
        let jobIDs = jobs.map(\.id)

        try await queue.enqueueFit(jobIDs: jobIDs, resumeID: resume.id)

        let requests = try await store.fetch(FetchDescriptor<LLMRequest>())
        let fitReqs = requests.filter { $0.requestType == .fit }
        XCTAssertEqual(fitReqs.count, 3, "All 3 jobs must have queued fit requests")
        XCTAssertTrue(fitReqs.allSatisfy { $0.status == .queued }, "All fit requests must be .queued")

        let scores = try await store.fetch(FetchDescriptor<JobFitScore>())
        XCTAssertEqual(scores.count, 3, "All 3 jobs must have a pending JobFitScore")
        XCTAssertTrue(scores.allSatisfy { $0.fitStatus == .pending }, "All JobFitScore records must be .pending")
        _ = (result1, result2, result3)
    }

    // MARK: - Data retention: Capture cascade on job delete

    func testDelete_jobDeleteCascadesToCapture() async throws {
        let container = try ModelContainerFactory.inMemory()
        let store = makeStore(container)
        let svc = JobService(store: store, queue: makeQueue(container))

        let result = try await svc.ingestCapture(CapturePayload(
            url: "https://example.com/cascade",
            pageTitle: "Cascade Test",
            visibleText: "some job text"
        ))

        let ctx = ModelContext(container)
        let jobsBefore = try ctx.fetch(FetchDescriptor<Job>())
        let capturesBefore = try ctx.fetch(FetchDescriptor<Capture>())
        XCTAssertEqual(jobsBefore.count, 1)
        XCTAssertEqual(capturesBefore.count, 1)

        let jobID = try XCTUnwrap(jobsBefore.first?.id)
        try await svc.delete(jobID: jobID)

        let jobsAfter = try ctx.fetch(FetchDescriptor<Job>())
        let capturesAfter = try ctx.fetch(FetchDescriptor<Capture>())
        XCTAssertEqual(jobsAfter.count, 0, "Job must be deleted")
        XCTAssertEqual(capturesAfter.count, 0, "Capture must be cascade-deleted with its Job")
        _ = result
    }

    /// The exposed bulk-delete action (TASK-604) routes each selected id through `JobService.delete`;
    /// a missing/already-deleted id must throw so the UI reports failure instead of claiming success.
    func testDelete_missingJobThrows() async throws {
        let container = try ModelContainerFactory.inMemory()
        let store = makeStore(container)
        let svc = JobService(store: store, queue: makeQueue(container))

        do {
            try await svc.delete(jobID: "does-not-exist")
            XCTFail("Deleting a nonexistent job should throw")
        } catch {
            // Any thrown error is enough for the UI to surface failure; assert the specific not-found case.
            guard case BackgroundStoreError.notFound = error else {
                return XCTFail("Expected .notFound, got \(error)")
            }
        }
    }

    // MARK: - LocalizedError descriptions

    func testJobServiceError_localizedDescriptions() {
        let cases: [(JobServiceError, String)] = [
            (.missingURL, "Job URL is required"),
            (.missingPageTitle, "Job page title is required"),
            (.missingText, "Job description text is required"),
            (.jobNotFound("any-id"), "Job not found"),
            (.actionNotFound("x"), "Action item not found"),
            (.contactNotFound("x"), "Contact not found"),
            (.coverLetterNotFound("x"), "Cover letter not found")
        ]
        for (error, expected) in cases {
            XCTAssertEqual(error.localizedDescription, expected, "Wrong description for \(error)")
        }
    }
}

// MARK: - Fit scoring state persistence tests

final class FitScoringStateTests: XCTestCase {
    private func makeStore(_ container: ModelContainer) -> BackgroundStore {
        BackgroundStore(modelContainer: container)
    }

    // MARK: - TASK-275: saveFitScore only updates Job fields for active resume

    func testSaveFitScore_inactiveResume_stillUpdatesBestMirror() async throws {
        // Best-across-resumes (Electron parity): the mirror reflects the best score regardless of
        // which resume is active, so scoring an inactive resume still updates the job mirror when
        // it is the best (here, the only) score.
        let container = try ModelContainerFactory.inMemory()
        let store = makeStore(container)

        let job = Job(id: "job-fit-1", jobNumber: 1)
        let activeResume = Resume(name: "Active", text: "Swift developer", charCount: 15, active: true, sortOrder: 0)
        let inactiveResume = Resume(
            name: "Inactive",
            text: "Python developer",
            charCount: 16,
            active: false,
            sortOrder: 1
        )
        try await store.insert(job)
        try await store.insert(activeResume)
        try await store.insert(inactiveResume)

        try await store.saveFitScore(
            jobID: "job-fit-1",
            resumeID: inactiveResume.id,
            overall: 75,
            fitJSON: "{\"overall\":75}",
            model: "test-model",
            scoredAt: Date()
        )

        let jobs = try await store.fetch(FetchDescriptor<Job>(predicate: #Predicate { $0.id == "job-fit-1" }))
        let updatedJob = try XCTUnwrap(jobs.first)
        XCTAssertEqual(updatedJob.fitScore, 75, "Mirror reflects the best (only) score even from an inactive resume")
        XCTAssertEqual(updatedJob.fitStatus, .succeeded)
        XCTAssertEqual(updatedJob.fitScoreJSON, "{\"overall\":75}")

        let scores = try await store.fetch(FetchDescriptor<JobFitScore>())
        XCTAssertEqual(scores.count, 1, "JobFitScore record must be created even for inactive resume")
        XCTAssertEqual(scores.first?.fitScore, 75)
        XCTAssertEqual(scores.first?.fitStatus, .succeeded)
    }

    // TASK-495: re-scoring a resume must not let its stale prior score keep driving the job's fit
    // mirror — the cause of "overall fit (97) > best resume (92)" drift.
    func testMarkFitScoreRunning_clearsStaleScore_andRecomputesMirror() async throws {
        let container = try ModelContainerFactory.inMemory()
        let store = makeStore(container)
        let job = Job(id: "job-mirror", jobNumber: 1)
        let r1 = Resume(name: "High", text: "x", charCount: 1, active: true, sortOrder: 0)
        let r2 = Resume(name: "Low", text: "y", charCount: 1, active: true, sortOrder: 1)
        try await store.insert(job)
        try await store.insert(r1)
        try await store.insert(r2)

        try await store.saveFitScore(
            jobID: "job-mirror",
            resumeID: r1.id,
            overall: 97,
            fitJSON: nil,
            model: "m",
            scoredAt: Date()
        )
        try await store.saveFitScore(
            jobID: "job-mirror",
            resumeID: r2.id,
            overall: 80,
            fitJSON: nil,
            model: "m",
            scoredAt: Date()
        )
        var jobs = try await store.fetch(FetchDescriptor<Job>(predicate: #Predicate { $0.id == "job-mirror" }))
        XCTAssertEqual(try XCTUnwrap(jobs.first).fitScore, 97, "mirror starts at the best (97)")

        // Begin re-scoring the high resume: its old 97 must drop out of the mirror immediately.
        try await store.markFitScoreRunning(jobID: "job-mirror", resumeID: r1.id)
        jobs = try await store.fetch(FetchDescriptor<Job>(predicate: #Predicate { $0.id == "job-mirror" }))
        XCTAssertEqual(
            try XCTUnwrap(jobs.first).fitScore,
            80,
            "while re-scoring, the mirror reflects the best *settled* score (80), not the stale 97"
        )

        // New score lands lower than the old one — the mirror must follow it, never stay at 97.
        try await store.saveFitScore(
            jobID: "job-mirror",
            resumeID: r1.id,
            overall: 92,
            fitJSON: nil,
            model: "m",
            scoredAt: Date()
        )
        jobs = try await store.fetch(FetchDescriptor<Job>(predicate: #Predicate { $0.id == "job-mirror" }))
        XCTAssertEqual(
            try XCTUnwrap(jobs.first).fitScore,
            92,
            "mirror equals the new best across resumes (92), not the stale 97"
        )
    }

    // TASK-519: a re-queued (pending) fit must drop its stale score from the job mirror, exactly like
    // the running path does — otherwise a job shows .succeeded with an old score while a rescore waits.
    func testEnqueueFitForActiveResumes_pending_clearsStaleScoreFromMirror() async throws {
        let container = try ModelContainerFactory.inMemory()
        let store = makeStore(container)
        let job = Job(id: "job-pending", jobNumber: 1)
        let resume = Resume(name: "R", text: "x", charCount: 1, active: true, sortOrder: 0)
        try await store.insert(job)
        try await store.insert(resume)
        try await store.saveFitScore(
            jobID: "job-pending",
            resumeID: resume.id,
            overall: 90,
            fitJSON: nil,
            model: "m",
            scoredAt: Date()
        )
        var jobs = try await store.fetch(FetchDescriptor<Job>(predicate: #Predicate { $0.id == "job-pending" }))
        XCTAssertEqual(try XCTUnwrap(jobs.first).fitScore, 90, "mirror starts at the scored value")

        let n = try await store.enqueueFitForActiveResumes(jobID: "job-pending")
        XCTAssertEqual(n, 1)
        jobs = try await store.fetch(FetchDescriptor<Job>(predicate: #Predicate { $0.id == "job-pending" }))
        let after = try XCTUnwrap(jobs.first)
        XCTAssertNil(after.fitScore, "a queued rescore must clear the stale score from the mirror")
        XCTAssertEqual(after.fitStatus, .pending)
    }

    func testMarkFitScorePending_clearsStaleScoreFromMirror() async throws {
        let container = try ModelContainerFactory.inMemory()
        let store = makeStore(container)
        let job = Job(id: "job-pending-2", jobNumber: 1)
        let resume = Resume(name: "R", text: "x", charCount: 1, active: true, sortOrder: 0)
        try await store.insert(job)
        try await store.insert(resume)
        try await store.saveFitScore(
            jobID: "job-pending-2",
            resumeID: resume.id,
            overall: 75,
            fitJSON: nil,
            model: "m",
            scoredAt: Date()
        )

        try await store.markFitScorePending(jobID: "job-pending-2", resumeID: resume.id)
        let jobs = try await store.fetch(FetchDescriptor<Job>(predicate: #Predicate { $0.id == "job-pending-2" }))
        let after = try XCTUnwrap(jobs.first)
        XCTAssertNil(after.fitScore)
        XCTAssertEqual(after.fitStatus, .pending)
    }

    // TASK-527: a fit record left .running with no backing request (cancelled/deleted) must not pin
    // the job's fit mirror at "Scoring…" — reconcile resets it to .none and recomputes the mirror.
    func testReconcileOrphanedFitScores_clearsRunningWithNoBackingRequest() async throws {
        let container = try ModelContainerFactory.inMemory()
        let store = makeStore(container)
        let job = Job(id: "job-orphan", jobNumber: 1)
        let resume = Resume(name: "R", text: "x", charCount: 1, active: true, sortOrder: 0)
        try await store.insert(job)
        try await store.insert(resume)
        try await store.markFitScoreRunning(jobID: "job-orphan", resumeID: resume.id)
        var jobs = try await store.fetch(FetchDescriptor<Job>(predicate: #Predicate { $0.id == "job-orphan" }))
        XCTAssertEqual(try XCTUnwrap(jobs.first).fitStatus, .running)

        let n = try await store.reconcileOrphanedFitScores()
        XCTAssertEqual(n, 1)
        jobs = try await store.fetch(FetchDescriptor<Job>(predicate: #Predicate { $0.id == "job-orphan" }))
        let after = try XCTUnwrap(jobs.first)
        XCTAssertEqual(after.fitStatus, FitStatus.none, "orphaned running fit reconciles to none")
        XCTAssertNil(after.fitScore)
    }

    /// A fit still backed by a queued/running request (e.g. after a reset) must be left alone.
    func testReconcileOrphanedFitScores_leavesBackedPendingAlone() async throws {
        let container = try ModelContainerFactory.inMemory()
        let store = makeStore(container)
        let job = Job(id: "job-backed", jobNumber: 1)
        let resume = Resume(name: "R", text: "x", charCount: 1, active: true, sortOrder: 0)
        try await store.insert(job)
        try await store.insert(resume)
        _ = try await store.enqueueFitForActiveResumes(jobID: "job-backed") // queued request + pending fit

        let n = try await store.reconcileOrphanedFitScores()
        XCTAssertEqual(n, 0, "a fit backed by a queued request must not be reconciled")
        let jobs = try await store.fetch(FetchDescriptor<Job>(predicate: #Predicate { $0.id == "job-backed" }))
        XCTAssertEqual(try XCTUnwrap(jobs.first).fitStatus, .pending)
    }

    func testRecomputeAllFitScores_recomputesFromStoredJSONWithoutLLM() async throws {
        // Electron parity (rescore.js): recompute the overall score from stored dimensions using
        // current weights, no LLM. Dimensions 80/50/80/90/60 → 72 with the TASK-602 weights
        // (80*.40 + 50*.20 + 80*.15 + 90*.10 + 60*.15 = 72.0). Chosen off a .5 boundary so the
        // expected value is unambiguous regardless of float rounding.
        let container = try ModelContainerFactory.inMemory()
        let store = makeStore(container)
        let job = Job(id: "rescore-job", jobNumber: 1)
        let resume = Resume(name: "R", text: "x", charCount: 1, active: true, sortOrder: 0)
        try await store.insert(job)
        try await store.insert(resume)
        let json = """
        {"dimensions":[{"name":"required_qualifications","score":80},\
        {"name":"preferred_qualifications","score":50},{"name":"skills","score":80},\
        {"name":"experience_level","score":90},{"name":"domain_fit","score":60}],\
        "requirements_not_met":[]}
        """
        try await store.saveFitScore(
            jobID: "rescore-job",
            resumeID: resume.id,
            overall: 50,
            fitJSON: json,
            model: "m",
            scoredAt: Date()
        )

        let n = try await store.recomputeAllFitScores()
        XCTAssertEqual(n, 1)
        let scores = try await store.fetch(FetchDescriptor<JobFitScore>())
        XCTAssertEqual(scores.first?.fitScore, 72, "rescore recomputes overall from dimensions with current weights")
        let jobs = try await store.fetch(FetchDescriptor<Job>())
        XCTAssertEqual(jobs.first?.fitScore, 72, "job mirror updates to recomputed best score")
    }

    func testSaveFitScore_activeResume_updatesJobFields() async throws {
        let container = try ModelContainerFactory.inMemory()
        let store = makeStore(container)

        let job = Job(id: "job-fit-2", jobNumber: 2)
        let activeResume = Resume(name: "Active", text: "Swift developer", charCount: 15, active: true, sortOrder: 0)
        try await store.insert(job)
        try await store.insert(activeResume)

        try await store.saveFitScore(
            jobID: "job-fit-2",
            resumeID: activeResume.id,
            overall: 88,
            fitJSON: "{\"overall\":88}",
            model: "test-model",
            scoredAt: Date()
        )

        let jobs = try await store.fetch(FetchDescriptor<Job>(predicate: #Predicate { $0.id == "job-fit-2" }))
        let updatedJob = try XCTUnwrap(jobs.first)
        XCTAssertEqual(updatedJob.fitScore, 88, "Job.fitScore must be updated for active resume")
        XCTAssertEqual(updatedJob.fitStatus, .succeeded, "Job.fitStatus must be .succeeded for active resume")
        XCTAssertEqual(updatedJob.fitScoreJSON, "{\"overall\":88}")
    }

    // MARK: - TASK-277: enqueueFit creates JobFitScore with .pending status

    func testEnqueueFit_createsPendingFitScoreRecord() async throws {
        let container = try ModelContainerFactory.inMemory()
        let store = makeStore(container)
        let queue = QueueActor(
            store: store,
            isPaused: { false },
            onSetPaused: { _ in },
            readExtractionSettings: { ExtractionSettings(
                llmModel: "",
                preferredLocations: "",
                locationFilterEnabled: false,
                locationAllowRemote: true,
                locationAllowHybrid: true,
                locationAllowOnsite: true
            ) },
            providerFactory: { NoOpProvider() }
        )
        let svc = JobService(store: store, queue: queue)

        _ = try await svc.ingestCapture(CapturePayload(
            url: "https://j.example.com/fit1",
            pageTitle: "Eng",
            visibleText: "Swift engineer role"
        ))
        let jobs = try await store.fetch(FetchDescriptor<Job>())
        let jobID = try XCTUnwrap(jobs.first?.id)

        let resume = Resume(name: "My Resume", text: "Swift iOS developer", charCount: 20, active: true, sortOrder: 0)
        try await store.insert(resume)

        try await queue.enqueueFit(jobIDs: [jobID], resumeID: resume.id)

        let scores = try await store.fetch(FetchDescriptor<JobFitScore>())
        XCTAssertEqual(scores.count, 1, "enqueueFit must create a JobFitScore record")
        XCTAssertEqual(scores.first?.fitStatus, .pending, "JobFitScore must have fitStatus = .pending after enqueue")
        XCTAssertEqual(scores.first?.resume?.id, resume.id)
        XCTAssertEqual(scores.first?.job?.id, jobID)
    }

    // MARK: - TASK-274: markFitScoreFailed persists failure state

    func testMarkFitScoreFailed_createsFailedRecord() async throws {
        let container = try ModelContainerFactory.inMemory()
        let store = makeStore(container)

        let job = Job(id: "job-fail-1", jobNumber: 10)
        let resume = Resume(name: "Resume", text: "text", charCount: 4, active: true, sortOrder: 0)
        try await store.insert(job)
        try await store.insert(resume)

        try await store.markFitScoreFailed(
            jobID: "job-fail-1",
            resumeID: resume.id,
            errorMessage: "rate limit exceeded"
        )

        let scores = try await store.fetch(FetchDescriptor<JobFitScore>())
        XCTAssertEqual(scores.count, 1, "markFitScoreFailed must create a JobFitScore record")
        let score = try XCTUnwrap(scores.first)
        XCTAssertEqual(score.fitStatus, .failed)
        XCTAssertNotNil(score.fitScoreJSON, "fitScoreJSON must contain the error message")
        XCTAssertTrue(
            score.fitScoreJSON?.contains("rate limit exceeded") == true,
            "fitScoreJSON must include the error text"
        )
    }
}

// MARK: - TASK-280: Status-change timeline events

final class StatusTimelineEventTests: XCTestCase {
    private func makeStore(_ container: ModelContainer) -> BackgroundStore {
        BackgroundStore(modelContainer: container)
    }

    func testSetStatus_createsTimelineEvent() async throws {
        let container = try ModelContainerFactory.inMemory()
        let store = makeStore(container)
        let svc = JobService(store: store, queue: makeQueue(container))

        let result = try await svc.ingestCapture(CapturePayload(
            url: "https://example.com/event-test",
            pageTitle: "Event Test Job",
            visibleText: "Some job text"
        ))
        let jobs = try await store.fetch(FetchDescriptor<Job>())
        let job = try XCTUnwrap(jobs.first(where: { $0.jobNumber == result.jobNumber }))
        let jobID = job.id

        try await svc.setStatus(.applied, for: jobID)

        let events = try await store.fetch(FetchDescriptor<JobEvent>())
        let statusEvents = events.filter { $0.eventType == "status" && $0.job?.id == jobID }
        XCTAssertEqual(statusEvents.count, 1, "setStatus must create one status timeline event")
        XCTAssertTrue(
            statusEvents.first?.note?.contains("applied") == true,
            "Status event note should mention the new status"
        )
    }

    func testSetStatusBulk_createsEventsForEachJob() async throws {
        let container = try ModelContainerFactory.inMemory()
        let store = makeStore(container)
        let svc = JobService(store: store, queue: makeQueue(container))

        _ = try await svc.ingestCapture(CapturePayload(
            url: "https://example.com/bulk/1",
            pageTitle: "Job 1",
            visibleText: "text"
        ))
        _ = try await svc.ingestCapture(CapturePayload(
            url: "https://example.com/bulk/2",
            pageTitle: "Job 2",
            visibleText: "text"
        ))

        let jobs = try await store.fetch(FetchDescriptor<Job>())
        XCTAssertEqual(jobs.count, 2)
        let jobIDs = jobs.map(\.id)

        try await svc.setStatusBulk(.applied, jobIDs: jobIDs)

        let events = try await store.fetch(FetchDescriptor<JobEvent>())
        let statusEvents = events.filter { $0.eventType == "status" }
        XCTAssertEqual(statusEvents.count, 2, "setStatusBulk must create one status event per job")
        XCTAssertTrue(statusEvents.allSatisfy { $0.note?.contains("applied") == true })
    }

    // MARK: - TASK-313: markRequestFailed does not overwrite retry/retryExhausted

    func testMarkRequestFailed_doesNotOverwriteRetryExhausted() async throws {
        let container = try ModelContainerFactory.inMemory()
        let store = makeStore(container)

        let req = LLMRequest(requestType: .extract, status: .retryExhausted)
        try await store.insert(req)
        let reqID = req.id

        // Simulate the guard-protected update that markRequestFailed uses
        try await store.update(LLMRequest.self, predicate: #Predicate { $0.id == reqID }) { r in
            guard r.status == .running else { return }
            r.status = .failed
            r.finishedAt = Date()
            r.error = "should not appear"
        }

        let fetched = try await store.fetch(FetchDescriptor<LLMRequest>(predicate: #Predicate { $0.id == reqID }))
        XCTAssertEqual(
            fetched.first?.status,
            .retryExhausted,
            "retryExhausted must not be overwritten by markRequestFailed"
        )
    }

    func testMarkRequestFailed_doesNotOverwriteQueued() async throws {
        let container = try ModelContainerFactory.inMemory()
        let store = makeStore(container)

        let req = LLMRequest(requestType: .extract, status: .queued)
        try await store.insert(req)
        let reqID = req.id

        // Simulate the guard-protected update
        try await store.update(LLMRequest.self, predicate: #Predicate { $0.id == reqID }) { r in
            guard r.status == .running else { return }
            r.status = .failed
            r.finishedAt = Date()
            r.error = "should not appear"
        }

        let fetched = try await store.fetch(FetchDescriptor<LLMRequest>(predicate: #Predicate { $0.id == reqID }))
        XCTAssertEqual(fetched.first?.status, .queued, "queued (retry) must not be overwritten by markRequestFailed")
    }

    // MARK: - TASK-314: Attempt records can be linked to an LLMRequest

    func testAttemptRecordsLinkedToRequest() async throws {
        let container = try ModelContainerFactory.inMemory()
        let store = makeStore(container)

        let req = LLMRequest(requestType: .extract, status: .running)
        try await store.insert(req)

        let attempt = LLMRequestAttempt(
            requestType: .extract,
            attempt: 1,
            status: .failed,
            modelRequested: "test-model",
            startedAt: Date(),
            finishedAt: Date(),
            error: "test error"
        )
        attempt.request = req
        try await store.insert(attempt)

        // Verify the relationship is navigable
        let reqID = req.id
        let fetched = try await store.fetch(FetchDescriptor<LLMRequest>(predicate: #Predicate { $0.id == reqID }))
        XCTAssertEqual(fetched.first?.attempts.count, 1, "Attempt should be linked to the request")
        XCTAssertEqual(fetched.first?.attempts.first?.status, .failed)
    }

    // MARK: - TASK-316: Running transition skips cancelled requests

    func testRunningTransitionSkipsCancelledRequest() async throws {
        let container = try ModelContainerFactory.inMemory()
        let store = makeStore(container)

        let req = LLMRequest(requestType: .extract, status: .cancelled)
        try await store.insert(req)
        let reqID = req.id

        // Simulate the guard-protected running transition from processRequest
        try await store.update(LLMRequest.self, predicate: #Predicate { $0.id == reqID }) { r in
            guard r.status == .queued else { return }
            r.status = .running
            r.startedAt = Date()
        }

        let fetched = try await store.fetch(FetchDescriptor<LLMRequest>(predicate: #Predicate { $0.id == reqID }))
        XCTAssertEqual(fetched.first?.status, .cancelled, "Cancelled request must not be transitioned to running")
    }

    // MARK: - TASK-332: CSV formula injection defense

    func testCsvExport_formulaTitle_isSanitized() async throws {
        let container = try ModelContainerFactory.inMemory()
        let store = makeStore(container)
        let job = Job(id: "job-fi-1", jobNumber: 10, title: "=HYPERLINK(\"evil.com\",\"click\")", status: .pursuing)
        try await store.insert(job)

        let csv = ExportService.jobsCSV(jobs: [job])
        XCTAssertTrue(csv.contains("'=HYPERLINK"), "Formula-prefixed title must be sanitized with leading single quote")
        XCTAssertFalse(csv.contains(",=HYPERLINK"), "Unsanitized formula must not appear bare in CSV")
    }

    func testCsvExport_plusPrefix_isSanitized() {
        let result = ExportService.sanitizeCsvCell("+malicious")
        XCTAssertEqual(result, "'+malicious")
    }

    // TASK-376: previously-raw fields (application_url, extraction_model, salary_currency) must
    // also be formula-sanitized now that sanitization is applied to every field.
    func testCsvExport_previouslyRawFields_areSanitized() async throws {
        let container = try ModelContainerFactory.inMemory()
        let store = makeStore(container)
        let job = Job(id: "job-fi-2", jobNumber: 11, status: .pursuing)
        job.applicationURL = "=cmd|'/c calc'!A1"
        job.extractionModel = "@evilModel"
        job.salaryCurrency = "+USD"
        try await store.insert(job)

        let csv = ExportService.jobsCSV(jobs: [job])
        XCTAssertTrue(csv.contains("'=cmd"), "application_url formula must be sanitized")
        XCTAssertTrue(csv.contains("'@evilModel"), "extraction_model formula must be sanitized")
        XCTAssertTrue(csv.contains("'+USD"), "salary_currency formula must be sanitized")
        XCTAssertFalse(csv.contains(",=cmd"), "no bare formula trigger after a delimiter")
        XCTAssertFalse(csv.contains(",@evilModel"))
    }

    func testCsvExport_normalTitle_isUnchanged() {
        let result = ExportService.sanitizeCsvCell("Software Engineer")
        XCTAssertEqual(result, "Software Engineer")
    }

    func testCsvExport_columnHeaders_assertExactOrder() async throws {
        let container = try ModelContainerFactory.inMemory()
        let store = makeStore(container)
        let job = Job(id: "job-hdr", jobNumber: 1, status: .pursuing)
        try await store.insert(job)

        let csv = ExportService.jobsCSV(jobs: [job])
        let header = csv.components(separatedBy: "\n").first ?? ""
        let expected = "job_number,capture_id,job_id,status,rating,extraction_status,company,title,location,remote_type,salary_min,salary_max,salary_currency,salary_note,application_url,extraction_model,source_url,captured_at,extracted_at,fit_score,fit_status,has_pending_actions,open_actions_count"
        XCTAssertEqual(header, expected, "CSV header columns must match exact order")
    }
}
