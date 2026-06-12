import SwiftData
import XCTest
@testable import JobhuntCore

final class ResumeServiceTests: XCTestCase {
    var container: ModelContainer!
    var store: BackgroundStore!
    var service: ResumeService!

    override func setUp() async throws {
        container = try ModelContainerFactory.inMemory()
        store = BackgroundStore(modelContainer: container)
        service = ResumeService(store: store)
    }

    override func tearDown() async throws {
        container = nil
        store = nil
        service = nil
    }

    // MARK: - Add

    func testAddFirstResumeIsActive() async throws {
        try await service.addResume(name: "Primary", text: "Swift engineer resume")

        let ctx = ModelContext(container)
        let resumes = try ctx.fetch(FetchDescriptor<Resume>())
        XCTAssertEqual(resumes.count, 1)
        XCTAssertTrue(resumes[0].active, "First resume should be active automatically")
    }

    func testAddSecondResumeIsNotActive() async throws {
        try await service.addResume(name: "Primary", text: "First resume")
        try await service.addResume(name: "Secondary", text: "Second resume")

        let ctx = ModelContext(container)
        let resumes = try ctx.fetch(FetchDescriptor<Resume>(sortBy: [SortDescriptor(\.sortOrder)]))
        XCTAssertEqual(resumes.count, 2)
        XCTAssertTrue(resumes[0].active)
        XCTAssertFalse(resumes[1].active, "Second resume should not be active by default")
    }

    // MARK: - Update

    func testUpdateResumeChangesFields() async throws {
        try await service.addResume(name: "Original", text: "Old text")

        let ctx = ModelContext(container)
        let id = try ctx.fetch(FetchDescriptor<Resume>()).first!.id
        try await service.updateResume(id: id, name: "Updated", text: "New text content")

        let updated = try ctx.fetch(FetchDescriptor<Resume>()).first!
        XCTAssertEqual(updated.name, "Updated")
        XCTAssertEqual(updated.text, "New text content")
        XCTAssertEqual(updated.charCount, "New text content".count)
    }

    func testUpdateResumeText_deletesFitScores() async throws {
        try await service.addResume(name: "R", text: "Original resume text")

        let ctx = ModelContext(container)
        let resume = try ctx.fetch(FetchDescriptor<Resume>()).first!

        // Seed a job with a fit score linked to this resume
        let job = Job(jobNumber: 42, title: "SWE")
        job.fitScore = 80
        job.fitStatus = .succeeded
        ctx.insert(job)
        let score = JobFitScore(fitScore: 80, fitStatus: .succeeded)
        score.job = job
        score.resume = resume
        ctx.insert(score)
        try ctx.save()

        try await service.updateResume(id: resume.id, name: "R", text: "Changed resume text")

        let scores = try ctx.fetch(FetchDescriptor<JobFitScore>())
        XCTAssertTrue(scores.isEmpty, "Fit scores should be deleted when resume text changes")

        let jobs = try ctx.fetch(FetchDescriptor<Job>())
        XCTAssertNil(jobs.first?.fitScore, "Job.fitScore should be cleared after score deletion")
        XCTAssertEqual(jobs.first?.fitStatus, FitStatus.none, "Job.fitStatus should be reset to .none")
    }

    func testUpdateResumeNameOnly_doesNotDeleteFitScores() async throws {
        try await service.addResume(name: "R", text: "Same resume text")

        let ctx = ModelContext(container)
        let resume = try ctx.fetch(FetchDescriptor<Resume>()).first!

        let job = Job(jobNumber: 43, title: "PM")
        job.fitScore = 75
        job.fitStatus = .succeeded
        ctx.insert(job)
        let score = JobFitScore(fitScore: 75, fitStatus: .succeeded)
        score.job = job
        score.resume = resume
        ctx.insert(score)
        try ctx.save()

        try await service.updateResume(id: resume.id, name: "Renamed", text: "Same resume text")

        let scores = try ctx.fetch(FetchDescriptor<JobFitScore>())
        XCTAssertEqual(scores.count, 1, "Fit scores should NOT be deleted when only name changes")
    }

    // MARK: - Delete

    func testDeleteInactiveResume() async throws {
        try await service.addResume(name: "Active", text: "Active resume")
        try await service.addResume(name: "Inactive", text: "Inactive resume")

        let ctx = ModelContext(container)
        let all = try ctx.fetch(FetchDescriptor<Resume>(sortBy: [SortDescriptor(\.sortOrder)]))
        let inactiveID = all.first(where: { !$0.active })!.id
        try await service.deleteResume(id: inactiveID)

        let remaining = try ctx.fetch(FetchDescriptor<Resume>())
        XCTAssertEqual(remaining.count, 1)
        XCTAssertTrue(remaining[0].active)
    }

    func testDeleteActiveResumePromotesNext() async throws {
        try await service.addResume(name: "First", text: "First resume")
        try await service.addResume(name: "Second", text: "Second resume")

        let ctx = ModelContext(container)
        let all = try ctx.fetch(FetchDescriptor<Resume>(sortBy: [SortDescriptor(\.sortOrder)]))
        let activeID = all.first(where: { $0.active })!.id
        try await service.deleteResume(id: activeID)

        let remaining = try ctx.fetch(FetchDescriptor<Resume>())
        XCTAssertEqual(remaining.count, 1)
        XCTAssertTrue(remaining[0].active, "Remaining resume should be promoted to active")
    }

    // MARK: - Activation

    func testSetActiveResumeSwitchesActiveFlag() async throws {
        try await service.addResume(name: "First", text: "First resume")
        try await service.addResume(name: "Second", text: "Second resume")

        let ctx = ModelContext(container)
        let all = try ctx.fetch(FetchDescriptor<Resume>(sortBy: [SortDescriptor(\.sortOrder)]))
        let secondID = all[1].id

        try await service.setActiveResume(id: secondID)

        let updated = try ctx.fetch(FetchDescriptor<Resume>(sortBy: [SortDescriptor(\.sortOrder)]))
        XCTAssertFalse(updated[0].active, "First resume should be deactivated")
        XCTAssertTrue(updated[1].active, "Second resume should be active")
    }

    // TASK-159: invalid activation must leave previous active resume unchanged
    func testSetActiveResume_invalidID_throwsAndLeavesActiveUnchanged() async throws {
        try await service.addResume(name: "Only", text: "Active resume")

        let ctx = ModelContext(container)
        let activeID = try ctx.fetch(FetchDescriptor<Resume>()).first!.id

        do {
            try await service.setActiveResume(id: "nonexistent-id")
            XCTFail("Expected resumeNotFound error")
        } catch ResumeServiceError.resumeNotFound {
            // expected
        }

        // The previously active resume must remain active.
        let after = try ctx.fetch(FetchDescriptor<Resume>())
        XCTAssertEqual(after.count, 1)
        XCTAssertTrue(after[0].active, "Active resume must remain active after invalid setActiveResume")
        XCTAssertEqual(after[0].id, activeID)
    }

    func testSetActiveResume_atMostOneActiveResume() async throws {
        try await service.addResume(name: "A", text: "Resume A")
        try await service.addResume(name: "B", text: "Resume B")
        try await service.addResume(name: "C", text: "Resume C")

        let ctx = ModelContext(container)
        let all = try ctx.fetch(FetchDescriptor<Resume>(sortBy: [SortDescriptor(\.sortOrder)]))
        try await service.setActiveResume(id: all[2].id)

        let updated = try ctx.fetch(FetchDescriptor<Resume>())
        let activeCount = updated.filter(\.active).count
        XCTAssertEqual(activeCount, 1, "Exactly one resume must be active")
        XCTAssertEqual(updated.first(where: \.active)?.name, "C")
    }

    // MARK: - TASK-306: Fit mirror recompute on active resume change

    func testSetActiveResume_recomputesJobFitMirrors() async throws {
        try await service.addResume(name: "Resume1", text: "First resume text")
        try await service.addResume(name: "Resume2", text: "Second resume text")

        let ctx = ModelContext(container)
        let resumes = try ctx.fetch(FetchDescriptor<Resume>(sortBy: [SortDescriptor(\.sortOrder)]))
        let r1 = resumes[0]
        let r2 = resumes[1]

        // Create a job and scores for both resumes
        let job = Job(jobNumber: 1, title: "SWE")
        ctx.insert(job)
        let score1 = JobFitScore(fitScore: 80, fitStatus: .succeeded)
        score1.job = job
        score1.resume = r1
        ctx.insert(score1)
        let score2 = JobFitScore(fitScore: 60, fitStatus: .succeeded)
        score2.job = job
        score2.resume = r2
        ctx.insert(score2)
        try ctx.save()

        // r1 starts active; set it explicitly and verify mirror
        try await service.setActiveResume(id: r1.id)
        let afterR1 = try ctx.fetch(FetchDescriptor<Job>()).first!
        XCTAssertEqual(afterR1.fitScore, 80, "Mirror should reflect resume-1 score")

        // Switch to r2
        try await service.setActiveResume(id: r2.id)
        let afterR2 = try ctx.fetch(FetchDescriptor<Job>()).first!
        XCTAssertEqual(afterR2.fitScore, 60, "Mirror should reflect resume-2 score")
        XCTAssertEqual(afterR2.fitStatus, .succeeded)

        // Switch back to r1
        try await service.setActiveResume(id: r1.id)
        let backToR1 = try ctx.fetch(FetchDescriptor<Job>()).first!
        XCTAssertEqual(backToR1.fitScore, 80, "Mirror should reflect resume-1 score again")
    }

    func testSetActiveResume_clearsJobMirrorWhenNoScore() async throws {
        try await service.addResume(name: "Resume1", text: "First resume text")
        try await service.addResume(name: "Resume2", text: "Second resume text")

        let ctx = ModelContext(container)
        let resumes = try ctx.fetch(FetchDescriptor<Resume>(sortBy: [SortDescriptor(\.sortOrder)]))
        let r1 = resumes[0]
        let r2 = resumes[1]

        // Score only for r1
        let job = Job(jobNumber: 2, title: "PM")
        ctx.insert(job)
        let score1 = JobFitScore(fitScore: 75, fitStatus: .succeeded)
        score1.job = job
        score1.resume = r1
        ctx.insert(score1)
        try ctx.save()

        // Activate r1, verify mirror
        try await service.setActiveResume(id: r1.id)
        let afterR1 = try ctx.fetch(FetchDescriptor<Job>()).first!
        XCTAssertEqual(afterR1.fitScore, 75)

        // Switch to r2 — no score, mirror should clear
        try await service.setActiveResume(id: r2.id)
        let afterR2 = try ctx.fetch(FetchDescriptor<Job>()).first!
        XCTAssertNil(afterR2.fitScore, "Mirror should be nil when active resume has no score")
        XCTAssertEqual(afterR2.fitStatus, .none)
    }

    // MARK: - TASK-307: Fit mirror recompute on delete active resume

    func testDeleteActiveResume_recomputesFromPromotedResume() async throws {
        try await service.addResume(name: "Resume1", text: "First resume text")
        try await service.addResume(name: "Resume2", text: "Second resume text")

        let ctx = ModelContext(container)
        let resumes = try ctx.fetch(FetchDescriptor<Resume>(sortBy: [SortDescriptor(\.sortOrder)]))
        let r1 = resumes[0]  // active
        let r2 = resumes[1]

        let job = Job(jobNumber: 3, title: "Dev")
        ctx.insert(job)
        let score1 = JobFitScore(fitScore: 80, fitStatus: .succeeded)
        score1.job = job
        score1.resume = r1
        ctx.insert(score1)
        let score2 = JobFitScore(fitScore: 60, fitStatus: .succeeded)
        score2.job = job
        score2.resume = r2
        ctx.insert(score2)
        try ctx.save()

        // Set r1 active and confirm mirror
        try await service.setActiveResume(id: r1.id)

        // Delete r1 — r2 gets promoted
        try await service.deleteResume(id: r1.id)

        let afterDelete = try ctx.fetch(FetchDescriptor<Job>()).first!
        XCTAssertEqual(afterDelete.fitScore, 60, "Mirror should reflect promoted resume-2 score")
    }

    func testDeleteActiveResume_clearsJobMirrorWhenNoRemainingResume() async throws {
        try await service.addResume(name: "Only", text: "Only resume")

        let ctx = ModelContext(container)
        let resume = try ctx.fetch(FetchDescriptor<Resume>()).first!

        let job = Job(jobNumber: 4, title: "Lead")
        ctx.insert(job)
        let score = JobFitScore(fitScore: 70, fitStatus: .succeeded)
        score.job = job
        score.resume = resume
        ctx.insert(score)
        try ctx.save()

        // Set active and confirm mirror
        try await service.setActiveResume(id: resume.id)

        // Delete the only resume
        try await service.deleteResume(id: resume.id)

        let afterDelete = try ctx.fetch(FetchDescriptor<Job>()).first!
        XCTAssertNil(afterDelete.fitScore, "Mirror should be nil when no resume remains")
        XCTAssertEqual(afterDelete.fitStatus, .none)
    }

    func testDeleteInactiveResume_doesNotAffectJobMirrors() async throws {
        try await service.addResume(name: "Active", text: "Active resume text")
        try await service.addResume(name: "Inactive", text: "Inactive resume text")

        let ctx = ModelContext(container)
        let resumes = try ctx.fetch(FetchDescriptor<Resume>(sortBy: [SortDescriptor(\.sortOrder)]))
        let r1 = resumes[0]  // active
        let r2 = resumes[1]  // inactive

        let job = Job(jobNumber: 5, title: "Engineer")
        ctx.insert(job)
        let score1 = JobFitScore(fitScore: 80, fitStatus: .succeeded)
        score1.job = job
        score1.resume = r1
        ctx.insert(score1)
        let score2 = JobFitScore(fitScore: 50, fitStatus: .succeeded)
        score2.job = job
        score2.resume = r2
        ctx.insert(score2)
        try ctx.save()

        // Confirm r1 is active and set mirror
        try await service.setActiveResume(id: r1.id)

        // Delete inactive r2 — should not affect mirror
        try await service.deleteResume(id: r2.id)

        let afterDelete = try ctx.fetch(FetchDescriptor<Job>()).first!
        XCTAssertEqual(afterDelete.fitScore, 80, "Mirror should be unchanged after deleting inactive resume")
    }

    // MARK: - TASK-310: updateOne path

    func testUpdateResume_throwsNotFoundForUnknownID() async throws {
        do {
            try await service.updateResume(id: "nonexistent-id", name: "X", text: "Y")
            XCTFail("Expected an error for unknown resume ID")
        } catch BackgroundStoreError.notFound {
            // expected — proves updateOne path is used
        }
    }
}

// MARK: - SavedSearchServiceTests (via JobService)

final class SavedSearchServiceTests: XCTestCase {
    var container: ModelContainer!
    var store: BackgroundStore!
    var jobService: JobService!

    override func setUp() async throws {
        container = try ModelContainerFactory.inMemory()
        store = BackgroundStore(modelContainer: container)
        let queue = QueueActor(
            store: store,
            isPaused: { false },
            onSetPaused: { _ in },
            readExtractionSettings: { ExtractionSettings(llmModel: "", preferredLocations: "", locationFilterEnabled: false, locationAllowRemote: true, locationAllowHybrid: true, locationAllowOnsite: true) },
            providerFactory: { NoOpProvider() }
        )
        jobService = JobService(store: store, queue: queue)
    }

    func testInsertSavedSearchPersists() async throws {
        let search = SavedSearch(name: "Remote Swift", sortOrder: 0)
        try await jobService.insertSavedSearch(search)

        let ctx = ModelContext(container)
        let all = try ctx.fetch(FetchDescriptor<SavedSearch>())
        XCTAssertEqual(all.count, 1)
        XCTAssertEqual(all[0].name, "Remote Swift")
    }

    func testDeleteSavedSearchRemovesIt() async throws {
        let search = SavedSearch(name: "To Delete", sortOrder: 0)
        try await jobService.insertSavedSearch(search)

        let ctx = ModelContext(container)
        let id = try ctx.fetch(FetchDescriptor<SavedSearch>()).first!.id
        try await jobService.deleteSavedSearch(id: id)

        let remaining = try ctx.fetch(FetchDescriptor<SavedSearch>())
        XCTAssertTrue(remaining.isEmpty)
    }
}

// MARK: - DuplicateUnmarkTests (via JobService)

final class DuplicateUnmarkTests: XCTestCase {
    var container: ModelContainer!
    var store: BackgroundStore!
    var jobService: JobService!

    override func setUp() async throws {
        container = try ModelContainerFactory.inMemory()
        store = BackgroundStore(modelContainer: container)
        let queue = QueueActor(
            store: store,
            isPaused: { false },
            onSetPaused: { _ in },
            readExtractionSettings: { ExtractionSettings(llmModel: "", preferredLocations: "", locationFilterEnabled: false, locationAllowRemote: true, locationAllowHybrid: true, locationAllowOnsite: true) },
            providerFactory: { NoOpProvider() }
        )
        jobService = JobService(store: store, queue: queue)
    }

    func testUnmarkDuplicateClearsDuplicateOfJobID() async throws {
        let original = Job(jobNumber: 1, title: "Original")
        let candidate = Job(jobNumber: 2, title: "Candidate")
        candidate.duplicateOfJobID = original.id
        try await store.insert(original)
        try await store.insert(candidate)

        try await jobService.unmarkDuplicate(jobID: candidate.id)

        let ctx = ModelContext(container)
        let all = try ctx.fetch(FetchDescriptor<Job>())
        let c = all.first(where: { $0.id == candidate.id })!
        XCTAssertNil(c.duplicateOfJobID, "duplicateOfJobID should be cleared after unmark")
    }

    func testDeleteJobRemovesIt() async throws {
        let job = Job(jobNumber: 10, title: "To Delete")
        try await store.insert(job)

        try await jobService.delete(jobID: job.id)

        let ctx = ModelContext(container)
        let all = try ctx.fetch(FetchDescriptor<Job>())
        XCTAssertTrue(all.isEmpty)
    }

    func testMarkExpiredSetsStatus() async throws {
        let job = Job(jobNumber: 5, title: "Gone Job")
        try await store.insert(job)

        try await jobService.markExpired(jobIDs: [job.id])

        let ctx = ModelContext(container)
        let all = try ctx.fetch(FetchDescriptor<Job>())
        XCTAssertEqual(all.first?.status, .expired)
    }
}

// MARK: - Stub

private struct NoOpProvider: LLMProvider {
    let id = "noop"; let concurrencyLimit = 1
    func complete(_: ChatRequest) async throws -> ChatResponse {
        throw LLMProviderError.httpError(statusCode: 503, body: "no-op")
    }
}
