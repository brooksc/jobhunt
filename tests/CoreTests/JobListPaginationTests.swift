import Foundation
import SwiftData
import XCTest
@testable import JobhuntCore

/// `jobs_list` returned a bare array capped at 200 with no offset, so a status with more rows was
/// partly unreachable and the truncation was invisible: 474 archived jobs answered as the 200 most
/// recent, with no total, no has_more, and no indication the requested limit wasn't honoured.
/// The queue is held paused throughout, so this never runs; it exists only to satisfy the actor's
/// initializer.
private struct ListPagingNoOpProvider: LLMProvider {
    let id = "noop"
    let concurrencyLimit = 1
    func complete(_: ChatRequest) async throws -> ChatResponse {
        throw LLMProviderError.unavailable(reason: "unused in list tests")
    }
}

final class JobListPaginationTests: XCTestCase {
    private var container: ModelContainer!
    private var store: BackgroundStore!
    private var svc: JobService!

    override func setUp() async throws {
        container = try ModelContainerFactory.inMemory()
        store = BackgroundStore(modelContainer: container)
        svc = JobService(
            store: store,
            queue: QueueActor(
                store: BackgroundStore(modelContainer: container),
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
                providerFactory: { ListPagingNoOpProvider() }
            )
        )
    }

    /// `count` archived rows, newest first by job number.
    private func seedArchived(_ count: Int) async throws {
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        for i in 0 ..< count {
            let job = Job(
                jobNumber: i + 1,
                company: "Company \(i % 7)",
                title: "Archived role \(i)",
                status: .archived,
                createdAt: base.addingTimeInterval(Double(i))
            )
            try await store.insert(job)
        }
    }

    // MARK: - The reported failure

    /// Every archived row must be reachable by paging — the whole point of the report.
    func testEveryRecordIsReachableByPaging() async throws {
        try await seedArchived(474)
        var seen = Set<Int>()
        var offset = 0
        var calls = 0
        while true {
            let page = try await svc.listJobs(JobQuery(status: "archived", offset: offset, limit: 200))
            XCTAssertEqual(page.total, 474, "total must be the full match count, not the page size")
            seen.formUnion(page.records.compactMap(\.jobNumber))
            calls += 1
            guard let next = page.nextOffset else { break }
            offset = next
            XCTAssertLessThan(calls, 10, "paging failed to terminate")
        }
        XCTAssertEqual(seen.count, 474, "every archived job must be retrievable")
        XCTAssertEqual(seen.min(), 1, "the oldest rows were the ones previously unreachable")
    }

    func testPagesDoNotOverlapOrSkip() async throws {
        try await seedArchived(250)
        let first = try await svc.listJobs(JobQuery(status: "archived", offset: 0, limit: 100))
        let second = try await svc.listJobs(JobQuery(status: "archived", offset: 100, limit: 100))
        let a = Set(first.records.map(\.id))
        let b = Set(second.records.map(\.id))
        XCTAssertEqual(a.count, 100)
        XCTAssertEqual(b.count, 100)
        XCTAssertTrue(a.isDisjoint(with: b), "pages must not repeat rows")
    }

    func testHasMoreAndNextOffsetReportTruncation() async throws {
        try await seedArchived(30)
        let page = try await svc.listJobs(JobQuery(status: "archived", limit: 10))
        XCTAssertEqual(page.total, 30)
        XCTAssertTrue(page.hasMore)
        XCTAssertEqual(page.nextOffset, 10)
    }

    func testFinalPageReportsNoMore() async throws {
        try await seedArchived(30)
        let page = try await svc.listJobs(JobQuery(status: "archived", offset: 20, limit: 10))
        XCTAssertEqual(page.records.count, 10)
        XCTAssertFalse(page.hasMore)
        XCTAssertNil(page.nextOffset)
    }

    func testOffsetPastTheEndIsEmptyNotAnError() async throws {
        try await seedArchived(5)
        let page = try await svc.listJobs(JobQuery(status: "archived", offset: 500, limit: 10))
        XCTAssertTrue(page.records.isEmpty)
        XCTAssertEqual(page.total, 5, "total still describes the corpus")
        XCTAssertFalse(page.hasMore)
    }

    // MARK: - Text search

    func testQueryMatchesTitle() async throws {
        try await seedArchived(20)
        let page = try await svc.listJobs(JobQuery(query: "Archived role 7", limit: 50))
        XCTAssertEqual(page.total, 1)
        XCTAssertEqual(page.records.first?.jobNumber, 8)
    }

    /// The use case from the report: keyword questions over the whole corpus without paging it all
    /// to the caller. The term lives only in the description.
    func testQueryMatchesTheCleanedDescription() async throws {
        // Ingest for real so the capture + cleaned description are wired the way production does it.
        _ = try await svc.ingestCapture(CapturePayload(
            url: "https://example.com/1",
            pageTitle: "Platform TPM",
            visibleText: "You will own our SOC 2 Type II and GDPR compliance programme."
        ))

        let hit = try await svc.listJobs(JobQuery(query: "soc 2", limit: 50))
        XCTAssertEqual(hit.total, 1, "must search description text, not just metadata")
        let miss = try await svc.listJobs(JobQuery(query: "kubernetes", limit: 50))
        XCTAssertEqual(miss.total, 0)
    }

    func testQueryIsCaseInsensitive() async throws {
        try await seedArchived(3)
        let page = try await svc.listJobs(JobQuery(query: "ARCHIVED ROLE", limit: 50))
        XCTAssertEqual(page.total, 3)
    }

    /// Filters combine, and `total` reflects the filtered set rather than the table.
    func testQueryAndStatusCombine() async throws {
        try await seedArchived(10)
        let live = Job(jobNumber: 999, title: "Archived role live", status: .pursuing)
        try await store.insert(live)

        let page = try await svc.listJobs(JobQuery(status: "archived", query: "Archived role", limit: 50))
        XCTAssertEqual(page.total, 10, "the pursuing row must not be counted")
    }

    // MARK: - Other filters

    func testCompanyFilter() async throws {
        try await seedArchived(21) // companies cycle 0…6, so each appears 3 times
        let page = try await svc.listJobs(JobQuery(company: "Company 3", limit: 50))
        XCTAssertEqual(page.total, 3)
    }

    func testMinSalaryUsesTheCeilingAndExcludesUnstated() async throws {
        let rich = Job(jobNumber: 1, title: "Rich", salaryMin: 150_000, salaryMax: 250_000, status: .new)
        let poor = Job(jobNumber: 2, title: "Poor", salaryMin: 80000, salaryMax: 120_000, status: .new)
        let silent = Job(jobNumber: 3, title: "Silent", status: .new)
        for job in [rich, poor, silent] {
            try await store.insert(job)
        }

        let page = try await svc.listJobs(JobQuery(minSalary: 200_000, limit: 50))
        XCTAssertEqual(page.records.map(\.jobNumber), [1], "only the ceiling that clears the floor")
    }

    func testCapturedAfterFilter() async throws {
        try await seedArchived(5)
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        let page = try await svc.listJobs(JobQuery(capturedAfter: base.addingTimeInterval(3), limit: 50))
        XCTAssertEqual(page.total, 2, "rows created at +3 and +4")
    }

    // MARK: - Fit score exposure

    /// The score was computed and stored but never projected into the MCP payload, so score-based
    /// triage ("which pursuing roles are above 85?") was impossible through the tool.
    func testListRecordsCarryTheFitScore() async throws {
        let job = Job(jobNumber: 1, title: "Scored", status: .pursuing)
        job.fitScore = 74
        job.fitStatus = .succeeded
        try await store.insert(job)

        let page = try await svc.listJobs(JobQuery(limit: 10))
        XCTAssertEqual(page.records.first?.fitScore, 74)
        XCTAssertEqual(page.records.first?.fitStatus, .succeeded)
    }

    func testMinScoreFiltersOnFit() async throws {
        for (number, score) in [(1, 92), (2, 74), (3, 45)] {
            let job = Job(jobNumber: number, title: "Job \(number)", status: .pursuing)
            job.fitScore = score
            job.fitStatus = .succeeded
            try await store.insert(job)
        }
        let page = try await svc.listJobs(JobQuery(minScore: 75, limit: 10))
        XCTAssertEqual(page.records.map(\.jobNumber), [1])
        XCTAssertEqual(page.total, 1)
    }

    /// An unscored job can't be shown to clear a threshold, so it must not pass one.
    func testMinScoreExcludesUnscoredJobs() async throws {
        let unscored = Job(jobNumber: 1, title: "Unscored", status: .pursuing)
        try await store.insert(unscored)
        let filtered = try await svc.listJobs(JobQuery(minScore: 1, limit: 10))
        XCTAssertTrue(filtered.records.isEmpty)
        // …but it's still reachable when no floor is asked for.
        let all = try await svc.listJobs(JobQuery(limit: 10))
        XCTAssertEqual(all.total, 1)
    }

    // MARK: - Metadata completeness

    /// `salary_min`/`salary_max` were exposed without the currency, so a EUR or CAD posting read as
    /// dollars — wrong data rather than missing data. Four postings in the corpus are non-USD.
    func testSalaryCurrencyAccompaniesTheAmounts() async throws {
        let euro = Job(
            jobNumber: 1, title: "Berlin PM",
            salaryMin: 145_000, salaryMax: 180_000, salaryCurrency: "EUR", status: .new
        )
        try await store.insert(euro)
        let page = try await svc.listJobs(JobQuery(limit: 10))
        XCTAssertEqual(page.records.first?.salaryCurrency, "EUR")
    }

    func testHourlyRatesAreExposed() async throws {
        let contract = Job(jobNumber: 1, title: "Contract", status: .new)
        contract.salaryHourlyMin = 80
        contract.salaryHourlyMax = 100
        try await store.insert(contract)
        let page = try await svc.listJobs(JobQuery(limit: 10))
        XCTAssertEqual(page.records.first?.salaryHourlyMin, 80)
        XCTAssertEqual(page.records.first?.salaryHourlyMax, 100)
    }

    /// The requirements verdict drives the app's triage filter, so a caller doing the same triage
    /// needs it.
    func testRequirementsVerdictIsExposed() async throws {
        let job = Job(jobNumber: 1, title: "Job", status: .pursuing)
        job.meetsCriteria = false
        try await store.insert(job)
        let page = try await svc.listJobs(JobQuery(limit: 10))
        XCTAssertEqual(page.records.first?.meetsCriteria, false)
    }

    /// `query` searches the cleaned description, but it wasn't retrievable — a caller could find a
    /// match and not see what matched, short of pulling the raw page dump.
    func testJobDetailExposesTheCleanedDescriptionAndAnalysis() async throws {
        _ = try await svc.ingestCapture(CapturePayload(
            url: "https://example.com/1", pageTitle: "Staff TPM",
            visibleText: "We need someone to own SOC 2 compliance across the platform."
        ))
        let all = try await store.fetch(FetchDescriptor<Job>())
        let job = try XCTUnwrap(all.first)
        job.extractedJSON = #"{"summary":"Own compliance","requirements":["SOC 2"],"skills":["Audit"]}"#
        try await store.save()

        let fetched: JobDetailRecord? = try await svc.getJob(byID: job.id)
        let detail = try XCTUnwrap(fetched)
        XCTAssertTrue((detail.cleanedDescription ?? "").contains("SOC 2"))
        XCTAssertEqual(detail.summary, "Own compliance")
        XCTAssertEqual(detail.requirements, ["SOC 2"])
        XCTAssertEqual(detail.skills, ["Audit"])
    }

    // MARK: - Contract

    func testInvalidStatusIsRejected() async throws {
        do {
            _ = try await svc.listJobs(JobQuery(status: "not-a-status", limit: 10))
            XCTFail("expected an error")
        } catch let error as JobServiceError {
            guard case .invalidStatus = error else { return XCTFail("wrong error: \(error)") }
        }
    }

    func testNegativeOffsetIsClampedRatherThanCrashing() async throws {
        try await seedArchived(3)
        let page = try await svc.listJobs(JobQuery(offset: -5, limit: 10))
        XCTAssertEqual(page.records.count, 3)
        XCTAssertEqual(page.offset, 0)
    }

    func testEmptyCorpusReportsZeroTotal() async throws {
        let page = try await svc.listJobs(JobQuery(limit: 50))
        XCTAssertEqual(page.total, 0)
        XCTAssertFalse(page.hasMore)
        XCTAssertNil(page.nextOffset)
    }
}
