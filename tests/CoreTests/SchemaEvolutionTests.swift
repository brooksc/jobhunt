import SwiftData
import XCTest
@testable import JobhuntCore

/// Demonstrates the test pattern for SwiftData schema evolution.
///
/// These tests do not introduce a production schema change — they prove the baseline:
/// data written with the current schema survives a container re-open with
/// JobhuntMigrationPlan applied. Future schema versions should add a test class
/// that follows this same pattern but opens the container a second time with
/// the new migration plan and verifies both old data integrity and new field defaults.
///
/// Pattern for future SchemaVN tests:
///   1. Open a file-backed container using SchemaV(N-1) models.
///   2. Insert representative test data (one instance of every migrated model).
///   3. Close the container (nil the reference, allow ARC to clean up).
///   4. Re-open the same file with JobhuntMigrationPlan and the new SchemaVN.
///   5. Assert all rows are present and new optional fields are nil (or expected default).
final class SchemaEvolutionTests: XCTestCase {

    // MARK: - Baseline: V1 store survives container re-open

    /// Regression guard: a Job with every current field set survives a container close/reopen.
    /// If a stored property is renamed or removed without a migration stage, the re-opened
    /// store will either fail to open or return nil/default for the affected field, failing here.
    func testV1FullJobRoundTripIsRegressionGuard() throws {
        let storeURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("schema_fullroundtrip_\(UUID().uuidString).store")
        defer { try? FileManager.default.removeItem(at: storeURL) }

        let schema = Schema(SchemaV1.models)
        let config = ModelConfiguration(url: storeURL)

        // --- Phase 1: write a Job with every stored field populated ---
        let container1 = try ModelContainer(for: schema, migrationPlan: JobhuntMigrationPlan.self, configurations: config)
        let ctx1 = ModelContext(container1)

        let capture = Capture(
            url: "https://jobs.example.com/eng",
            canonicalURL: "https://jobs.example.com/engineering",
            pageTitle: "Senior Engineer",
            selectedText: "We are hiring.",
            visibleText: "Full page text here.",
            rawHash: "regression_guard_hash_\(UUID().uuidString)"
        )
        ctx1.insert(capture)

        let job = Job(
            jobNumber: 9001,
            company: "RegressionCo",
            title: "Senior Engineer",
            location: "Remote",
            remoteType: .remote,
            salaryMin: 100_000,
            salaryMax: 150_000,
            salaryCurrency: "USD",
            salaryNote: "Base only",
            employmentType: "full_time",
            seniority: "senior",
            status: .pursuing,
            manualOverridesJSON: "[]",
            extractedJSON: "{\"title\":\"Senior Engineer\"}",
            extractionStatus: .succeeded,
            fitScore: 88,
            fitStatus: .succeeded,
            rating: 4,
            extractionModel: "gpt-4o",
            applicationURL: "https://jobs.example.com/apply",
            extractionConfidence: 0.95,
            unread: true,
            createdAt: Date(timeIntervalSince1970: 1_000_000),
            updatedAt: Date(timeIntervalSince1970: 2_000_000)
        )
        job.capture = capture
        job.capturedAtDenormalized = capture.capturedAt
        ctx1.insert(job)
        try ctx1.save()

        let jobID = job.id

        // --- Phase 2: reopen with the same migration plan and verify every field ---
        let container2 = try ModelContainer(for: schema, migrationPlan: JobhuntMigrationPlan.self, configurations: config)
        let ctx2 = ModelContext(container2)

        let jobs = try ctx2.fetch(FetchDescriptor<Job>())
        XCTAssertEqual(jobs.count, 1, "Job must survive container re-open")
        let j = try XCTUnwrap(jobs.first)
        XCTAssertEqual(j.id, jobID)
        XCTAssertEqual(j.jobNumber, 9001)
        XCTAssertEqual(j.company, "RegressionCo")
        XCTAssertEqual(j.title, "Senior Engineer")
        XCTAssertEqual(j.location, "Remote")
        XCTAssertEqual(j.remoteType, .remote)
        XCTAssertEqual(j.salaryMin, 100_000)
        XCTAssertEqual(j.salaryMax, 150_000)
        XCTAssertEqual(j.salaryCurrency, "USD")
        XCTAssertEqual(j.salaryNote, "Base only")
        XCTAssertEqual(j.employmentType, "full_time")
        XCTAssertEqual(j.seniority, "senior")
        XCTAssertEqual(j.status, .pursuing)
        XCTAssertEqual(j.manualOverridesJSON, "[]")
        XCTAssertEqual(j.extractedJSON, "{\"title\":\"Senior Engineer\"}")
        XCTAssertEqual(j.extractionStatus, .succeeded)
        XCTAssertEqual(j.fitScore, 88)
        XCTAssertEqual(j.fitStatus, .succeeded)
        XCTAssertEqual(j.rating, 4)
        XCTAssertEqual(j.extractionModel, "gpt-4o")
        XCTAssertEqual(j.applicationURL, "https://jobs.example.com/apply")
        XCTAssertEqual(j.extractionConfidence ?? 0, 0.95, accuracy: 0.001)
        XCTAssertTrue(j.unread)
        XCTAssertEqual(j.createdAt.timeIntervalSince1970, 1_000_000, accuracy: 1)
        XCTAssertEqual(j.updatedAt.timeIntervalSince1970, 2_000_000, accuracy: 1)
        XCTAssertNotNil(j.capturedAtDenormalized)

        let captures = try ctx2.fetch(FetchDescriptor<Capture>())
        XCTAssertEqual(captures.count, 1, "Capture must survive container re-open")
        XCTAssertEqual(captures.first?.selectedText, "We are hiring.")
        XCTAssertEqual(captures.first?.canonicalURL, "https://jobs.example.com/engineering")
    }

    func testV1StoreRoundTripWithMigrationPlan() throws {
        // Use a temp file so we can close and re-open it.
        let storeURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("schema_test_\(UUID().uuidString).store")
        defer { try? FileManager.default.removeItem(at: storeURL) }

        let schema = Schema(SchemaV1.models)
        let config = ModelConfiguration(url: storeURL)

        // --- Phase 1: write data with current schema ---
        let container1 = try ModelContainer(for: schema, migrationPlan: JobhuntMigrationPlan.self, configurations: config)
        let ctx1 = ModelContext(container1)

        let job = Job(jobNumber: 42, title: "Schema Test Job")
        job.company = "EvolutionCo"
        ctx1.insert(job)
        try ctx1.save()

        let resume = Resume(name: "Test Resume", text: "Swift developer", charCount: 15, active: true, sortOrder: 0)
        ctx1.insert(resume)
        try ctx1.save()

        // Close by releasing the container reference
        let jobID = job.id
        let resumeID = resume.id
        // (container1 goes out of scope at end of block)

        // --- Phase 2: re-open with the same migration plan ---
        let container2 = try ModelContainer(for: schema, migrationPlan: JobhuntMigrationPlan.self, configurations: config)
        let ctx2 = ModelContext(container2)

        let jobs = try ctx2.fetch(FetchDescriptor<Job>())
        XCTAssertEqual(jobs.count, 1, "Job should survive container re-open")
        XCTAssertEqual(jobs.first?.id, jobID)
        XCTAssertEqual(jobs.first?.title, "Schema Test Job")
        XCTAssertEqual(jobs.first?.company, "EvolutionCo")
        XCTAssertEqual(jobs.first?.jobNumber, 42)

        let resumes = try ctx2.fetch(FetchDescriptor<Resume>())
        XCTAssertEqual(resumes.count, 1, "Resume should survive container re-open")
        XCTAssertEqual(resumes.first?.id, resumeID)
        XCTAssertTrue(resumes.first?.active ?? false)
    }

    func testAllV1ModelTypesCanBeInsertedAndFetched() throws {
        let container = try ModelContainerFactory.inMemory()
        let ctx = ModelContext(container)

        // Verify all model types registered in SchemaV1 can be inserted without error.
        // This test fails fast if any model's initializer or schema definition is broken.
        let capture = Capture(url: "https://example.com/job", pageTitle: "Title", rawHash: "hash1")
        let job = Job(jobNumber: 100, title: "V1 Test")
        job.capture = capture
        ctx.insert(capture)
        ctx.insert(job)

        let site = Site(origin: "example.com", url: "https://example.com")
        ctx.insert(site)

        let setting = Setting(key: "test_key", value: "test_val")
        ctx.insert(setting)

        let resume = Resume(name: "Resume", text: "text", charCount: 4, active: true, sortOrder: 0)
        ctx.insert(resume)

        try ctx.save()

        XCTAssertEqual(try ctx.fetch(FetchDescriptor<Job>()).count, 1)
        XCTAssertEqual(try ctx.fetch(FetchDescriptor<Site>()).count, 1)
        XCTAssertEqual(try ctx.fetch(FetchDescriptor<Resume>()).count, 1)
    }

    // MARK: - Migration plan structure invariants

    func testMigrationPlanSchemasIncludeV1() {
        let schemas = JobhuntMigrationPlan.schemas
        XCTAssertTrue(
            schemas.contains { $0 == SchemaV1.self },
            "JobhuntMigrationPlan must include SchemaV1"
        )
    }

    func testMigrationPlanSchemasAreOrdered() {
        // Schemas must be ordered oldest → newest. V1 must be first.
        let schemas = JobhuntMigrationPlan.schemas
        XCTAssertEqual(schemas.first?.versionIdentifier, SchemaV1.versionIdentifier)
    }

    func testSchemaV1ContainsAllExpectedModels() {
        let modelTypeNames = SchemaV1.models.map { String(describing: $0) }
        let expected = ["Capture", "Job", "Resume", "Site", "Setting", "LLMRequest", "SavedSearch"]
        for name in expected {
            XCTAssertTrue(modelTypeNames.contains(name), "SchemaV1 should include \(name)")
        }
    }

    // MARK: - Compile-time property stability guard

    /// Every stored property on every SchemaV1 model is read here.
    /// If a property is renamed or removed without adding a new VersionedSchema,
    /// this test FAILS TO COMPILE — surfacing the breaking change before it ships.
    ///
    /// When you need to rename or remove a stored property:
    ///   1. Follow the SchemaV2 process in Schema.swift (copy model, bump version, add stage).
    ///   2. Update this test to use the new property names.
    ///
    /// When you ADD a new optional property (backward-compatible lightweight migration):
    ///   No new VersionedSchema is needed — just add the property read below.
    // swiftlint:disable:next function_body_length
    func testSchemaV1StoredPropertyNamesAreStable() throws {
        let container = try ModelContainerFactory.inMemory()
        let ctx = ModelContext(container)

        // Capture
        let cap = Capture(url: "https://example.com", pageTitle: "T", rawHash: "h")
        ctx.insert(cap)
        _ = cap.id; _ = cap.url; _ = cap.canonicalURL; _ = cap.pageTitle
        _ = cap.selectedText; _ = cap.visibleText; _ = cap.cleanedDescription
        _ = cap.structuredDataJSON; _ = cap.userNote; _ = cap.rawHash
        _ = cap.cleanedHash; _ = cap.capturedAt; _ = cap.createdAt; _ = cap.job

        // Job
        let job = Job(jobNumber: 1, title: "T")
        ctx.insert(job)
        _ = job.id; _ = job.jobNumber; _ = job.company; _ = job.title; _ = job.location
        _ = job.remoteType; _ = job.salaryMin; _ = job.salaryMax; _ = job.salaryCurrency
        _ = job.salaryNote; _ = job.employmentType; _ = job.seniority; _ = job.status
        _ = job.manualOverridesJSON; _ = job.extractedJSON; _ = job.extractionStatus
        _ = job.extractionError; _ = job.fitScore; _ = job.fitStatus; _ = job.fitScoreJSON
        _ = job.duplicateOfJobID; _ = job.duplicateConfidence; _ = job.extractedAt
        _ = job.rating; _ = job.extractionModel; _ = job.applicationURL
        _ = job.extractionConfidence; _ = job.lastOpenedAt; _ = job.unread
        _ = job.createdAt; _ = job.updatedAt; _ = job.rawTextBytes; _ = job.cleanedTextBytes
        _ = job.capturedAtDenormalized
        _ = job.capture; _ = job.events; _ = job.actions; _ = job.contacts
        _ = job.coverLetters; _ = job.fitScores; _ = job.llmRequests; _ = job.qualityReview

        // JobEvent
        let ev = JobEvent(eventType: "applied")
        ctx.insert(ev)
        _ = ev.id; _ = ev.eventType; _ = ev.note; _ = ev.occurredAt; _ = ev.createdAt; _ = ev.job

        // SiteReview
        let sr = SiteReview(siteURL: "https://x.com/jobs", siteOrigin: "https://x.com")
        ctx.insert(sr)
        _ = sr.id; _ = sr.siteURL; _ = sr.siteOrigin; _ = sr.pageTitle; _ = sr.reviewedAt
        _ = sr.nextReviewAt; _ = sr.note; _ = sr.createdAt

        // DuplicateDecision
        let dd = DuplicateDecision(cleanedHash: "hash1", decision: "keep")
        ctx.insert(dd)
        _ = dd.cleanedHash; _ = dd.decision; _ = dd.keepJobID; _ = dd.note
        _ = dd.decidedAt; _ = dd.createdAt

        // Setting
        let setting = Setting(key: "k", value: "v")
        ctx.insert(setting)
        _ = setting.key; _ = setting.value; _ = setting.updatedAt

        // JobAction
        let action = JobAction(note: "n", dueDate: Date())
        ctx.insert(action)
        _ = action.id; _ = action.note; _ = action.dueDate; _ = action.completedAt
        _ = action.snoozedUntil; _ = action.createdAt; _ = action.updatedAt; _ = action.job

        // DataQualityReview
        let dqr = DataQualityReview()
        ctx.insert(dqr)
        _ = dqr.reviewedAt; _ = dqr.note; _ = dqr.job

        // Site
        let site = Site(origin: "https://x.com", url: "https://x.com/jobs")
        ctx.insert(site)
        _ = site.id; _ = site.origin; _ = site.url; _ = site.companyName
        _ = site.companyWebsite; _ = site.jobsURL; _ = site.companyDescription
        _ = site.pageTitle; _ = site.intervalDays; _ = site.lastReviewedAt
        _ = site.nextReviewAt; _ = site.note; _ = site.state
        _ = site.addedAt; _ = site.createdAt; _ = site.updatedAt

        // Resume
        let resume = Resume(name: "R", text: "t", charCount: 1, active: true, sortOrder: 0)
        ctx.insert(resume)
        _ = resume.id; _ = resume.name; _ = resume.filename; _ = resume.text
        _ = resume.charCount; _ = resume.active; _ = resume.sortOrder
        _ = resume.createdAt; _ = resume.updatedAt; _ = resume.fitScores

        // JobFitScore
        let jfs = JobFitScore()
        ctx.insert(jfs)
        _ = jfs.fitScore; _ = jfs.fitStatus; _ = jfs.fitScoreJSON; _ = jfs.model
        _ = jfs.scoredAt; _ = jfs.createdAt; _ = jfs.updatedAt; _ = jfs.job; _ = jfs.resume

        // LLMRequest
        let llmReq = LLMRequest()
        ctx.insert(llmReq)
        _ = llmReq.id; _ = llmReq.requestType; _ = llmReq.status; _ = llmReq.attempt
        _ = llmReq.model; _ = llmReq.error; _ = llmReq.createdAt
        _ = llmReq.startedAt; _ = llmReq.finishedAt
        _ = llmReq.job; _ = llmReq.resume; _ = llmReq.attempts

        // LLMRequestAttempt
        let att = LLMRequestAttempt(requestType: .extract, attempt: 1, status: .queued)
        ctx.insert(att)
        _ = att.id; _ = att.requestType; _ = att.attempt; _ = att.status
        _ = att.modelRequested; _ = att.modelReturned; _ = att.responseFormat; _ = att.baseURL
        _ = att.startedAt; _ = att.finishedAt; _ = att.durationMs; _ = att.error
        _ = att.responsePreview; _ = att.promptChars; _ = att.responseChars
        _ = att.request; _ = att.job

        // Contact
        let contact = Contact(name: "Alice")
        ctx.insert(contact)
        _ = contact.id; _ = contact.name; _ = contact.role; _ = contact.email
        _ = contact.linkedinURL; _ = contact.phone; _ = contact.notes
        _ = contact.createdAt; _ = contact.updatedAt; _ = contact.job

        // CoverLetter
        let cl = CoverLetter(content: "c")
        ctx.insert(cl)
        _ = cl.id; _ = cl.content; _ = cl.instructions; _ = cl.model
        _ = cl.createdAt; _ = cl.job

        // SavedSearch
        let ss = SavedSearch(name: "test")
        ctx.insert(ss)
        _ = ss.id; _ = ss.name; _ = ss.sortOrder; _ = ss.createdAt
        _ = ss.searchText; _ = ss.minFitScore; _ = ss.minRating; _ = ss.minSalary
        _ = ss.recentDays; _ = ss.sortKeyRaw; _ = ss.sortAscending

        try ctx.save()
    }

    // MARK: - Compile-time property TYPE stability guard (TASK-368 / TASK-369)

    /// Companion to `testSchemaV1StoredPropertyNamesAreStable`. That guard only *reads* each
    /// property, so a stored property whose *type* changes (e.g. `Int` → `String`, optional →
    /// non-optional) still compiles there but is a breaking SwiftData schema change that would
    /// corrupt or fail to open a shipped store. Here every storage-critical property is bound to
    /// an explicitly-typed `let`, so a type change FAILS TO COMPILE — surfacing the break before
    /// it ships. This is the "equivalent historical schema strategy" (TASK-368): it freezes the
    /// V1 stored shape without duplicating every model into a snapshot namespace.
    ///
    /// When you intentionally change a stored type, follow the SchemaV2 process in Schema.swift
    /// (copy model, bump version, add a migration stage) and then update the binding below.
    // swiftlint:disable:next function_body_length
    func testSchemaV1StoredPropertyTypesAreStable() throws {
        let container = try ModelContainerFactory.inMemory()
        let ctx = ModelContext(container)

        // Job
        let job = Job(jobNumber: 1, title: "T")
        ctx.insert(job)
        let _: String = job.id
        let _: Int? = job.jobNumber
        let _: String? = job.company
        let _: String? = job.title
        let _: String? = job.location
        let _: RemoteType? = job.remoteType
        let _: Int? = job.salaryMin
        let _: Int? = job.salaryMax
        let _: Double? = job.salaryHourlyMin
        let _: Double? = job.salaryHourlyMax
        let _: String? = job.salaryCurrency
        let _: String? = job.salaryNote
        let _: String? = job.employmentType
        let _: String? = job.seniority
        let _: JobStatus = job.status
        let _: String = job.manualOverridesJSON
        let _: String? = job.manualFieldOverridesJSON
        let _: String? = job.extractedJSON
        let _: ExtractionStatus = job.extractionStatus
        let _: String? = job.extractionError
        let _: Int? = job.fitScore
        let _: FitStatus = job.fitStatus
        let _: String? = job.fitScoreJSON
        let _: String? = job.duplicateOfJobID
        let _: Double? = job.duplicateConfidence
        let _: Date? = job.extractedAt
        let _: Int? = job.rating
        let _: String? = job.extractionModel
        let _: String? = job.applicationURL
        let _: Double? = job.extractionConfidence
        let _: Date? = job.lastOpenedAt
        let _: Bool = job.unread
        let _: Date = job.createdAt
        let _: Date = job.updatedAt
        let _: Int? = job.rawTextBytes
        let _: Int? = job.cleanedTextBytes
        let _: Date? = job.capturedAtDenormalized

        // Capture
        let cap = Capture(url: "https://example.com", pageTitle: "T", rawHash: "h")
        ctx.insert(cap)
        let _: String = cap.id
        let _: String = cap.url
        let _: String? = cap.canonicalURL
        let _: String = cap.pageTitle
        let _: String? = cap.selectedText
        let _: String? = cap.visibleText
        let _: String? = cap.cleanedDescription
        let _: String? = cap.structuredDataJSON
        let _: String? = cap.userNote
        let _: String = cap.rawHash
        let _: String? = cap.cleanedHash
        let _: Date = cap.capturedAt
        let _: Date = cap.createdAt

        // Resume
        let resume = Resume(name: "R", text: "t", charCount: 1, active: true, sortOrder: 0)
        ctx.insert(resume)
        let _: String = resume.id
        let _: String = resume.name
        let _: String? = resume.filename
        let _: String = resume.text
        let _: Int = resume.charCount
        let _: Bool = resume.active
        let _: Int = resume.sortOrder
        let _: Date = resume.createdAt
        let _: Date = resume.updatedAt

        // Site
        let site = Site(origin: "https://x.com", url: "https://x.com/jobs")
        ctx.insert(site)
        let _: String = site.id
        let _: String = site.url
        let _: String? = site.companyName
        let _: String? = site.companyWebsite
        let _: String? = site.jobsURL
        let _: String = site.companyDescription
        let _: String = site.pageTitle
        let _: Int = site.intervalDays
        let _: Date? = site.lastReviewedAt
        let _: Date? = site.nextReviewAt
        let _: String = site.note
        let _: SiteState = site.state
        let _: Date = site.addedAt
        let _: Date = site.createdAt
        let _: Date = site.updatedAt

        // LLMRequest
        let llmReq = LLMRequest()
        ctx.insert(llmReq)
        let _: String = llmReq.id
        let _: LLMRequestType = llmReq.requestType
        let _: LLMRequestStatus = llmReq.status
        let _: Int = llmReq.attempt
        let _: String? = llmReq.model
        let _: String? = llmReq.error
        let _: Date = llmReq.createdAt
        let _: Date? = llmReq.startedAt
        let _: Date? = llmReq.finishedAt

        // LLMRequestAttempt
        let att = LLMRequestAttempt(requestType: .extract, attempt: 1, status: .queued)
        ctx.insert(att)
        let _: String = att.id
        let _: LLMRequestType = att.requestType
        let _: Int = att.attempt
        let _: LLMRequestStatus = att.status
        let _: String? = att.modelRequested
        let _: String? = att.modelReturned
        let _: String? = att.responseFormat
        let _: String? = att.baseURL
        let _: Date = att.startedAt
        let _: Date? = att.finishedAt
        let _: Int? = att.durationMs
        let _: String? = att.error
        let _: String? = att.responsePreview
        let _: Int? = att.promptChars
        let _: Int? = att.responseChars

        // JobFitScore
        let jfs = JobFitScore()
        ctx.insert(jfs)
        let _: Int? = jfs.fitScore
        let _: FitStatus = jfs.fitStatus
        let _: String? = jfs.fitScoreJSON
        let _: String? = jfs.model
        let _: Date? = jfs.scoredAt
        let _: Date = jfs.createdAt
        let _: Date = jfs.updatedAt

        // SavedSearch
        let ss = SavedSearch(name: "test")
        ctx.insert(ss)
        let _: String = ss.id
        let _: String = ss.name
        let _: Int = ss.sortOrder
        let _: Date = ss.createdAt
        let _: [String] = ss.statusFilterRaw
        let _: [String] = ss.remoteFilterRaw
        let _: String = ss.searchText
        let _: Int? = ss.minFitScore
        let _: Int? = ss.minRating
        let _: Int? = ss.minSalary
        let _: Int? = ss.recentDays
        let _: String = ss.sortKeyRaw
        let _: Bool = ss.sortAscending

        try ctx.save()
    }
}
