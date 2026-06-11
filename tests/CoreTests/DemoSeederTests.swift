import SwiftData
import XCTest
@testable import JobhuntCore

final class DemoSeederTests: XCTestCase {
    // MARK: - Helpers

    func makeStore() throws -> (ModelContainer, BackgroundStore) {
        let container = try ModelContainerFactory.inMemory()
        let store = BackgroundStore(modelContainer: container)
        return (container, store)
    }

    // MARK: - seedDemo

    func testSeedDemoPopulatesJobs() async throws {
        let (container, store) = try makeStore()
        try await DemoSeeder.seedDemo(into: store)

        let ctx = ModelContext(container)
        let jobs = try ctx.fetch(FetchDescriptor<Job>())
        XCTAssertEqual(jobs.count, 15, "seedDemo must insert exactly 15 jobs")
    }

    func testSeedDemoPopulatesSites() async throws {
        let (container, store) = try makeStore()
        try await DemoSeeder.seedDemo(into: store)

        let ctx = ModelContext(container)
        let sites = try ctx.fetch(FetchDescriptor<Site>())
        XCTAssertEqual(sites.count, 3, "seedDemo must insert exactly 3 sites")
    }

    func testSeedDemoPopulatesResumes() async throws {
        let (container, store) = try makeStore()
        try await DemoSeeder.seedDemo(into: store)

        let ctx = ModelContext(container)
        let resumes = try ctx.fetch(FetchDescriptor<Resume>())
        XCTAssertEqual(resumes.count, 2, "seedDemo must insert exactly 2 resumes")
    }

    func testSeedDemoPopulatesCaptures() async throws {
        let (container, store) = try makeStore()
        try await DemoSeeder.seedDemo(into: store)

        let ctx = ModelContext(container)
        let captures = try ctx.fetch(FetchDescriptor<Capture>())
        XCTAssertEqual(captures.count, 15, "seedDemo must insert one capture per job (15)")
    }

    func testSeedDemoPopulatesEvents() async throws {
        let (container, store) = try makeStore()
        try await DemoSeeder.seedDemo(into: store)

        let ctx = ModelContext(container)
        let events = try ctx.fetch(FetchDescriptor<JobEvent>())
        // At minimum: notes on several jobs + status_change events for non-saved jobs
        XCTAssertGreaterThan(events.count, 0, "seedDemo must insert job events")
    }

    func testSeedDemoJobStatusVariety() async throws {
        let (container, store) = try makeStore()
        try await DemoSeeder.seedDemo(into: store)

        let ctx = ModelContext(container)
        let jobs = try ctx.fetch(FetchDescriptor<Job>())
        let statuses = Set(jobs.map(\.status))

        XCTAssertTrue(statuses.contains(.offer), "Must include at least one offer job")
        XCTAssertTrue(statuses.contains(.interview), "Must include at least one interview job")
        XCTAssertTrue(statuses.contains(.applied), "Must include at least one applied job")
        XCTAssertTrue(statuses.contains(.pursuing), "Must include at least one saved job")
        XCTAssertTrue(statuses.contains(.rejected), "Must include at least one rejected job")
        XCTAssertTrue(statuses.contains(.passed), "Must include at least one passed job")
    }

    func testSeedDemoJobsHaveFitScores() async throws {
        let (container, store) = try makeStore()
        try await DemoSeeder.seedDemo(into: store)

        let ctx = ModelContext(container)
        let jobs = try ctx.fetch(FetchDescriptor<Job>())
        let scored = jobs.filter { $0.fitScore != nil }
        XCTAssertGreaterThan(scored.count, 5, "Must have multiple jobs with fit scores")
    }

    func testSeedDemoJobsPendingExtraction() async throws {
        let (container, store) = try makeStore()
        try await DemoSeeder.seedDemo(into: store)

        let ctx = ModelContext(container)
        let jobs = try ctx.fetch(FetchDescriptor<Job>())
        let pending = jobs.filter { $0.extractionStatus == .pending }
        XCTAssertGreaterThan(pending.count, 0, "Must have some pending-extraction jobs")
    }

    func testSeedDemoHasDuplicateJob() async throws {
        let (container, store) = try makeStore()
        try await DemoSeeder.seedDemo(into: store)

        let ctx = ModelContext(container)
        let jobs = try ctx.fetch(FetchDescriptor<Job>())
        let duplicates = jobs.filter { $0.duplicateOfJobID != nil }
        XCTAssertEqual(duplicates.count, 1, "Must include exactly one duplicate job")
        XCTAssertEqual(duplicates.first?.duplicateOfJobID, "job_009")
    }

    func testSeedDemoIdempotent() async throws {
        let (container, store) = try makeStore()
        try await DemoSeeder.seedDemo(into: store)
        try await DemoSeeder.seedDemo(into: store) // second call should be a no-op

        let ctx = ModelContext(container)
        let jobs = try ctx.fetch(FetchDescriptor<Job>())
        XCTAssertEqual(jobs.count, 15, "Second seedDemo call must not duplicate data")
    }

    // MARK: - reseedDemo

    func testReseedDemoResetsCleanly() async throws {
        let (container, store) = try makeStore()
        try await DemoSeeder.seedDemo(into: store)

        // Add a user-created artifact to confirm it gets wiped
        let ctx = ModelContext(container)
        ctx.insert(Job(jobNumber: 999, company: "UserJob"))
        try ctx.save()

        let beforeJobs = try ctx.fetch(FetchDescriptor<Job>())
        XCTAssertEqual(beforeJobs.count, 16)

        try await DemoSeeder.reseedDemo(into: store)

        let afterJobs = try ctx.fetch(FetchDescriptor<Job>())
        XCTAssertEqual(afterJobs.count, 15, "reseedDemo must reset to exactly 15 jobs")
        let userJob = afterJobs.first { $0.jobNumber == 999 }
        XCTAssertNil(userJob, "reseedDemo must remove user-added jobs")
    }

    func testReseedDemoClearsEvents() async throws {
        let (container, store) = try makeStore()
        try await DemoSeeder.seedDemo(into: store)

        let ctx = ModelContext(container)
        let beforeEvents = try ctx.fetch(FetchDescriptor<JobEvent>())
        let countBefore = beforeEvents.count

        try await DemoSeeder.reseedDemo(into: store)

        let afterEvents = try ctx.fetch(FetchDescriptor<JobEvent>())
        // After reseed the event count should match original seed (same data)
        XCTAssertEqual(afterEvents.count, countBefore, "reseedDemo must restore same event count")
    }

    func testReseedDemoReplacesSites() async throws {
        let (container, store) = try makeStore()
        try await DemoSeeder.seedDemo(into: store)

        // Add an extra site
        let ctx = ModelContext(container)
        ctx.insert(Site(origin: "https://extra.com", url: "https://extra.com/jobs"))
        try ctx.save()
        XCTAssertEqual(try ctx.fetch(FetchDescriptor<Site>()).count, 4)

        try await DemoSeeder.reseedDemo(into: store)

        let afterSites = try ctx.fetch(FetchDescriptor<Site>())
        XCTAssertEqual(afterSites.count, 3, "reseedDemo must reset to exactly 3 sites")
    }

    // MARK: - Container isolation

    func testDemoContainerIsolatedFromUserContainer() async throws {
        let userContainer = try ModelContainerFactory.inMemory()
        let userCtx = ModelContext(userContainer)
        userCtx.insert(Job(jobNumber: 1, company: "UserCompany"))
        try userCtx.save()

        let demoContainer = try await ModelContainerFactory.demo()
        let demoCtx = ModelContext(demoContainer)
        let demoJobs = try demoCtx.fetch(FetchDescriptor<Job>())

        // Demo must have 15 seeded jobs
        XCTAssertEqual(demoJobs.count, 15)

        // User container must be untouched
        let userJobs = try userCtx.fetch(FetchDescriptor<Job>())
        XCTAssertEqual(userJobs.count, 1)
        XCTAssertEqual(userJobs.first?.company, "UserCompany")

        // Demo must not contain the user's job
        let userJobInDemo = demoJobs.first { $0.company == "UserCompany" }
        XCTAssertNil(userJobInDemo, "Demo container must be isolated from user container")
    }

    func testModelContainerFactoryDemoProducesSeededContainer() async throws {
        let container = try await ModelContainerFactory.demo()
        let ctx = ModelContext(container)
        let jobs = try ctx.fetch(FetchDescriptor<Job>())
        XCTAssertEqual(jobs.count, 15)
        let sites = try ctx.fetch(FetchDescriptor<Site>())
        XCTAssertEqual(sites.count, 3)
    }

    // MARK: - DemoMode enum

    func testDemoModeValues() {
        // Verify the DemoMode enum exists and has expected cases
        let live = DemoMode.live
        let demo = DemoMode.demo
        XCTAssertNotEqual("\(live)", "\(demo)")
    }
}
