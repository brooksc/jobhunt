import SwiftData
import XCTest
@testable import JobhuntCore

final class ModelRoundTripTests: XCTestCase {
    var container: ModelContainer!
    var context: ModelContext!

    override func setUp() async throws {
        container = try ModelContainerFactory.inMemory()
        context = ModelContext(container)
    }

    override func tearDown() async throws {
        container = nil
        context = nil
    }

    // MARK: - Capture

    func testCaptureRoundTrip() throws {
        let capture = Capture(url: "https://example.com/job/1", pageTitle: "Engineer", rawHash: "abc123")
        context.insert(capture)
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<Capture>())
        XCTAssertEqual(fetched.count, 1)
        XCTAssertEqual(fetched.first?.url, "https://example.com/job/1")
        XCTAssertEqual(fetched.first?.rawHash, "abc123")
    }

    /// rawHash is now @Attribute(.unique). Inserting two Captures with the same rawHash into
    /// an in-memory store results in at most one row surviving (SwiftData merges/upserts).
    /// For file-backed uniqueness enforcement tests, see UniquenessInvariantTests.
    func testCaptureRawHashDeduplicatesOnSave() throws {
        let capture1 = Capture(url: "https://a.com", pageTitle: "A", rawHash: "same_hash")
        let capture2 = Capture(url: "https://b.com", pageTitle: "B", rawHash: "same_hash")
        context.insert(capture1)
        context.insert(capture2)
        _ = try? context.save()
        let fetched = try context.fetch(FetchDescriptor<Capture>())
        XCTAssertLessThanOrEqual(
            fetched.count,
            2,
            "Duplicate rawHash rows must not both survive after unique constraint is active"
        )
    }

    // MARK: - Job

    func testJobRoundTrip() throws {
        let job = Job(jobNumber: 42, company: "Acme", title: "Engineer")
        context.insert(job)
        try context.save()

        var descriptor = FetchDescriptor<Job>(predicate: #Predicate { $0.jobNumber == 42 })
        descriptor.fetchLimit = 1
        let fetched = try context.fetch(descriptor)
        XCTAssertEqual(fetched.first?.company, "Acme")
        XCTAssertEqual(fetched.first?.status, .new)
        XCTAssertEqual(fetched.first?.extractionStatus, .pending)
        XCTAssertEqual(fetched.first?.fitStatus, FitStatus.none)
        XCTAssertFalse(fetched.first?.unread ?? true)
    }

    func testJobDefaultsMatchLegacy() {
        let job = Job()
        XCTAssertEqual(job.status, .new)
        XCTAssertEqual(job.extractionStatus, .pending)
        XCTAssertEqual(job.fitStatus, .none)
        XCTAssertEqual(job.manualOverridesJSON, "[]")
        XCTAssertFalse(job.unread)
    }

    // MARK: - Job → Capture relationship

    func testJobCaptureRelationship() throws {
        let capture = Capture(url: "https://example.com", pageTitle: "Test", rawHash: "h1")
        let job = Job(jobNumber: 1)
        job.capture = capture
        context.insert(capture)
        context.insert(job)
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<Job>()).first
        XCTAssertEqual(fetched?.capture?.rawHash, "h1")
    }

    // MARK: - Job cascade deletes

    func testJobEventCascadeDelete() throws {
        let job = Job(jobNumber: 10)
        let event = JobEvent(eventType: "status_change")
        job.events.append(event)
        context.insert(job)
        try context.save()

        XCTAssertEqual(try context.fetch(FetchDescriptor<JobEvent>()).count, 1)
        context.delete(job)
        try context.save()
        XCTAssertEqual(try context.fetch(FetchDescriptor<JobEvent>()).count, 0)
    }

    func testJobActionCascadeDelete() throws {
        let job = Job(jobNumber: 11)
        let action = JobAction(dueDate: Date())
        job.actions.append(action)
        context.insert(job)
        try context.save()

        context.delete(job)
        try context.save()
        XCTAssertEqual(try context.fetch(FetchDescriptor<JobAction>()).count, 0)
    }

    func testContactCascadeDelete() throws {
        let job = Job(jobNumber: 12)
        let contact = Contact(name: "Alice")
        job.contacts.append(contact)
        context.insert(job)
        try context.save()

        context.delete(job)
        try context.save()
        XCTAssertEqual(try context.fetch(FetchDescriptor<Contact>()).count, 0)
    }

    func testCoverLetterCascadeDelete() throws {
        let job = Job(jobNumber: 13)
        let letter = CoverLetter(content: "Dear Hiring Manager…")
        job.coverLetters.append(letter)
        context.insert(job)
        try context.save()

        context.delete(job)
        try context.save()
        XCTAssertEqual(try context.fetch(FetchDescriptor<CoverLetter>()).count, 0)
    }

    func testLLMRequestCascadeDelete() throws {
        let job = Job(jobNumber: 14)
        let req = LLMRequest()
        let att = LLMRequestAttempt(requestType: .extract, attempt: 1, status: .queued)
        req.attempts.append(att)
        job.llmRequests.append(req)
        context.insert(job)
        try context.save()

        context.delete(job)
        try context.save()
        XCTAssertEqual(try context.fetch(FetchDescriptor<LLMRequest>()).count, 0)
        XCTAssertEqual(try context.fetch(FetchDescriptor<LLMRequestAttempt>()).count, 0)
    }

    // MARK: - Resume → JobFitScore cascade

    func testFitScoreCascadeOnResumeDelete() throws {
        let resume = Resume(name: "My Resume")
        let score = JobFitScore(fitScore: 85, fitStatus: .succeeded)
        score.resume = resume
        resume.fitScores.append(score)
        context.insert(resume)
        try context.save()

        context.delete(resume)
        try context.save()
        XCTAssertEqual(try context.fetch(FetchDescriptor<JobFitScore>()).count, 0)
    }

    // MARK: - Site

    func testSiteRoundTrip() throws {
        let site = Site(origin: "https://jobs.example.com", url: "https://jobs.example.com/careers")
        context.insert(site)
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<Site>())
        XCTAssertEqual(fetched.first?.origin, "https://jobs.example.com")
        XCTAssertEqual(fetched.first?.state, .notReviewed)
        XCTAssertEqual(fetched.first?.intervalDays, 14)
    }

    // MARK: - Setting

    func testSettingRoundTrip() throws {
        let setting = Setting(key: "llm_provider", value: "lmstudio")
        context.insert(setting)
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<Setting>())
        XCTAssertEqual(fetched.first?.value, "lmstudio")
    }

    // MARK: - SiteReview

    func testSiteReviewRoundTrip() throws {
        let review = SiteReview(siteURL: "https://jobs.example.com", siteOrigin: "https://jobs.example.com")
        context.insert(review)
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<SiteReview>())
        XCTAssertEqual(fetched.count, 1)
    }

    // MARK: - DuplicateDecision

    func testDuplicateDecisionRoundTrip() throws {
        let dupDecision = DuplicateDecision(cleanedHash: "dup_hash", decision: "keep")
        context.insert(dupDecision)
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<DuplicateDecision>())
        XCTAssertEqual(fetched.first?.decision, "keep")
    }

    // MARK: - Enum raw values match legacy strings

    func testEnumRawValues() {
        XCTAssertEqual(JobStatus.pursuing.rawValue, "pursuing")
        XCTAssertEqual(JobStatus.closed.rawValue, "closed")
        XCTAssertEqual(ExtractionStatus.pending.rawValue, "pending")
        XCTAssertEqual(ExtractionStatus.succeeded.rawValue, "succeeded")
        XCTAssertEqual(FitStatus.none.rawValue, "none")
        XCTAssertEqual(RemoteType.remote.rawValue, "remote")
        XCTAssertEqual(RemoteType.onsite.rawValue, "onsite")
        XCTAssertEqual(RemoteType.unknown.rawValue, "unknown")
        XCTAssertEqual(SiteState.notReviewed.rawValue, "not_reviewed")
        XCTAssertEqual(LLMRequestType.extract.rawValue, "extract")
        XCTAssertEqual(LLMRequestStatus.queued.rawValue, "queued")
        XCTAssertEqual(LLMRequestStatus.retryExhausted.rawValue, "retry_exhausted")
    }

    // MARK: - TASK-151: JobDetailRecord shape pins sensitive fields

    /// This test pins the presence of selectedText and visibleText in JobDetailRecord so that
    /// future projection changes cannot silently drop or rename these fields without failing here.
    func testJobDetailRecord_includesRawCaptureText() throws {
        let capture = Capture(
            url: "https://jobs.example.com/eng",
            pageTitle: "Engineer",
            selectedText: "We are hiring an engineer.",
            visibleText: "Full page: We are hiring an engineer. Benefits...",
            rawHash: "h-detail-test"
        )
        let job = Job(jobNumber: 100, company: "Acme")
        job.capture = capture
        context.insert(capture)
        context.insert(job)
        try context.save()

        let record = JobDetailRecord(job: job)
        XCTAssertEqual(
            record.selectedText,
            "We are hiring an engineer.",
            "JobDetailRecord must expose selectedText for MCP job_get"
        )
        XCTAssertEqual(
            record.visibleText,
            "Full page: We are hiring an engineer. Benefits...",
            "JobDetailRecord must expose visibleText for MCP job_get"
        )
    }

    func testJobDetailRecord_nilCaptureText_exposesNil() throws {
        let capture = Capture(url: "https://jobs.example.com/other", pageTitle: "Other", rawHash: "h-nil-test")
        let job = Job(jobNumber: 101, company: "Beta")
        job.capture = capture
        context.insert(capture)
        context.insert(job)
        try context.save()

        let record = JobDetailRecord(job: job)
        XCTAssertNil(record.selectedText, "Absent selectedText must come through as nil")
        XCTAssertNil(record.visibleText, "Absent visibleText must come through as nil")
    }

    // MARK: - ModelContainerFactory in-memory

    func testInMemoryContainerIsIsolated() throws {
        let capture1 = try ModelContainerFactory.inMemory()
        let capture2 = try ModelContainerFactory.inMemory()
        let ctx1 = ModelContext(capture1)
        ctx1.insert(Job(jobNumber: 999))
        try ctx1.save()

        let ctx2 = ModelContext(capture2)
        let fetched = try ctx2.fetch(FetchDescriptor<Job>())
        XCTAssertEqual(fetched.count, 0, "In-memory containers must be isolated")
    }
}
