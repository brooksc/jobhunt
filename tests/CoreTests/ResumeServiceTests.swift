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
}
