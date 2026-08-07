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

    func testSeedDemoPopulatesSavedSearches() async throws {
        let (container, store) = try makeStore()
        try await DemoSeeder.seedDemo(into: store)

        let ctx = ModelContext(container)
        let searches = try ctx.fetch(FetchDescriptor<SavedSearch>(sortBy: [SortDescriptor(\.sortOrder)]))
        XCTAssertEqual(searches.map(\.name), ["Active Pipeline", "Remote Only — High Fit", "Needs Action — Applied"])
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

    /// Demo mode is what a prospective user clicks first, and the Fit tab is the feature they came to
    /// evaluate. The seeder previously emitted a legacy `{score, strengths, gaps}` shape that
    /// `FitScoreProjection` doesn't parse, so that tab rendered completely empty — no requirement
    /// rows, no dimension bars, no correction flags — and nothing caught it.
    func testSeedDemoFitScoresRenderAsANonEmptyProjection() async throws {
        let (container, store) = try makeStore()
        try await DemoSeeder.seedDemo(into: store)

        let ctx = ModelContext(container)
        // The Fit tab renders from job.fitScores, so that relationship — not the Job mirror — is
        // what has to be populated.
        let rows = try ctx.fetch(FetchDescriptor<JobFitScore>())
        XCTAssertGreaterThan(rows.count, 5, "no per-resume score rows: the Fit tab shows its empty state")

        for row in rows {
            let projection = FitScoreProjection(fitScore: row)
            XCTAssertFalse(
                projection.requirementAssessments.isEmpty,
                "score row has no requirement rows — the Fit tab would be blank"
            )
            XCTAssertFalse(projection.dimensions.isEmpty, "score row has no dimensions")
            XCTAssertNotNil(row.resume, "score row must be attached to a resume")
        }
    }

    /// A headline score that disagrees with the breakdown under it reads as a bug to anyone
    /// evaluating the app, so the stored score must be the one the scorer derives from the analysis.
    func testSeedDemoStoredScoreMatchesItsOwnAnalysis() async throws {
        let (container, store) = try makeStore()
        try await DemoSeeder.seedDemo(into: store)

        let ctx = ModelContext(container)
        for row in try ctx.fetch(FetchDescriptor<JobFitScore>()) {
            guard let json = row.fitScoreJSON else { continue }
            XCTAssertEqual(
                FitScorer.rescoreFromJSON(json)?.overall, row.fitScore,
                "stored score contradicts its own requirement assessments"
            )
            XCTAssertEqual(row.job?.fitScore, row.fitScore, "Job mirror disagrees with the score row")
        }
    }

    /// Both a gap and a met row must appear somewhere, or the demo can't show what the flag is for.
    func testSeedDemoIncludesBothMetAndUnmetRequirements() async throws {
        let (container, store) = try makeStore()
        try await DemoSeeder.seedDemo(into: store)

        let ctx = ModelContext(container)
        var statuses = Set<String>()
        for row in try ctx.fetch(FetchDescriptor<JobFitScore>()) {
            guard let json = row.fitScoreJSON,
                  let data = json.data(using: .utf8),
                  let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let items = dict["requirement_assessments"] as? [[String: Any]] else { continue }
            statuses.formUnion(items.compactMap { $0["status"] as? String })
        }
        XCTAssertTrue(statuses.contains("met"), "no met requirements across the demo corpus")
        XCTAssertTrue(
            statuses.contains("partial") || statuses.contains("missing"),
            "no gaps across the demo corpus — the correction flow can't be demonstrated"
        )
    }

    /// A prospective user's first instinct in demo mode is to capture a real job. Against the old
    /// 280-character stub résumés, real postings scored **0** — nothing was evidenced, the penalty
    /// saturated, and the product looked broken. Length isn't the goal, but it's the cheap proxy for
    /// "has employment history and evidence" rather than "is a summary sentence".
    func testDemoResumesAreFullDocumentsNotStubs() async throws {
        let (container, store) = try makeStore()
        try await DemoSeeder.seedDemo(into: store)

        let ctx = ModelContext(container)
        let resumes = try ctx.fetch(FetchDescriptor<Resume>())
        for resume in resumes {
            XCTAssertGreaterThan(
                resume.text.count, 1000,
                "\(resume.name) is \(resume.text.count) chars — too thin to evidence real requirements"
            )
            XCTAssertEqual(
                resume.charCount, resume.text.count,
                "\(resume.name): charCount drifted from the text it describes"
            )
        }

        // The evidence a scorer actually keys on: employers, dates, metrics and named tools.
        let full = try XCTUnwrap(resumes.first { $0.active })
        for marker in ["Northwind Cloud", "2021", "Kubernetes", "OKR", "SQL"] {
            XCTAssertTrue(full.text.contains(marker), "active résumé is missing \(marker)")
        }
    }

    /// Every seeded job that is a real posting carries a fit score.
    ///
    /// Replaces an assertion that some jobs sit at `.pending` extraction. That state existed to show
    /// variety, but on screen it reads as broken rather than as pending: a list peppered with
    /// score-less rows makes the scoring look failed and makes sort-and-filter-by-fit look like they
    /// don't work. The walkthrough demonstrates the pending state properly by capturing a job live
    /// and letting it extract on camera, which is the honest way to show it.
    ///
    /// The single exception is the accidentally-captured TechCrunch article, which has no score
    /// because it isn't a job — the point it exists to make.
    func testEveryRealPostingIsScored() async throws {
        let (container, store) = try makeStore()
        try await DemoSeeder.seedDemo(into: store)

        let ctx = ModelContext(container)
        let jobs = try ctx.fetch(FetchDescriptor<Job>())
        let unscored = jobs.filter { $0.fitScore == nil }
        XCTAssertEqual(
            unscored.count, 1,
            "Only the non-job page may be unscored; found: \(unscored.map { $0.title ?? "untitled" })"
        )
        XCTAssertNil(unscored.first?.title, "The unscored row must be the non-job capture")
        XCTAssertTrue(
            jobs.allSatisfy { $0.extractionStatus != .pending },
            "A permanently-pending row reads as a stuck queue in screenshots"
        )
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

    func testReseedDemoReplacesSavedSearches() async throws {
        let (container, store) = try makeStore()
        try await DemoSeeder.seedDemo(into: store)

        let ctx = ModelContext(container)
        ctx.insert(SavedSearch(name: "User Search"))
        try ctx.save()

        try await DemoSeeder.reseedDemo(into: store)

        let searches = try ctx.fetch(FetchDescriptor<SavedSearch>())
        XCTAssertEqual(searches.count, 3)
        XCTAssertFalse(searches.contains { $0.name == "User Search" })
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
