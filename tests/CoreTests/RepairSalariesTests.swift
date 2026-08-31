import SwiftData
import XCTest
@testable import JobhuntCore

/// Tests for BackgroundStore.repairStoredSalaries — the one-time repair for bands the old range
/// parser invented out of any two dash-separated numbers (job #1502 stored $2,020–$2,023 from a
/// "(2020-2023)" awards line).
final class RepairSalariesTests: XCTestCase {
    private func makeJob(
        number: Int,
        description: String,
        note: String? = nil,
        min: Int? = nil,
        max: Int? = nil,
        currency: String? = "USD",
        overrides: String? = nil
    ) -> (Job, Capture) {
        let capture = Capture(
            url: "https://example.com/job/\(number)",
            pageTitle: "Product Manager",
            visibleText: description,
            cleanedDescription: description,
            rawHash: "rh-salary-\(number)"
        )
        let job = Job(jobNumber: number, title: "Product Manager")
        job.capture = capture
        job.salaryNote = note
        job.salaryMin = min
        job.salaryMax = max
        job.salaryCurrency = currency
        job.manualFieldOverridesJSON = overrides
        return (job, capture)
    }

    private func store(_ pairs: [(Job, Capture)]) async throws -> BackgroundStore {
        let store = try BackgroundStore(modelContainer: ModelContainerFactory.inMemory())
        for (job, capture) in pairs {
            try await store.insert(capture)
            try await store.insert(job)
        }
        return store
    }

    private func job(_ store: BackgroundStore, _ number: Int) async throws -> Job {
        let rows = try await store.fetch(
            FetchDescriptor<Job>(predicate: #Predicate { $0.jobNumber == number })
        )
        return try XCTUnwrap(rows.first)
    }

    /// The reported case: no pay stated anywhere, so the invented band is removed.
    func testYearRangeBandIsCleared() async throws {
        let store = try await store([makeJob(
            number: 1502,
            description: "Named among the Best Places to Work in Insurance for four years in a row (2020-2023).",
            min: 2020,
            max: 2023
        )])

        let result = try await store.repairStoredSalaries()
        XCTAssertEqual(result.cleared, 1)
        XCTAssertEqual(result.corrected, 0)

        let repaired = try await job(store, 1502)
        XCTAssertNil(repaired.salaryMin)
        XCTAssertNil(repaired.salaryMax)
        XCTAssertNil(repaired.salaryCurrency)
    }

    func testRepairIsIdempotent() async throws {
        let store = try await store([makeJob(
            number: 1502,
            description: "Best Places to Work in Insurance (2020-2023).",
            min: 2020,
            max: 2023
        )])
        _ = try await store.repairStoredSalaries()
        let second = try await store.repairStoredSalaries()
        XCTAssertEqual(second.cleared, 0)
        XCTAssertEqual(second.corrected, 0)
    }

    /// A posting that DOES state pay gets the real band, not the one the old parser picked up first.
    func testStatedPayReplacesTheInventedBand() async throws {
        let store = try await store([makeJob(
            number: 7,
            description: """
            Recognized as a top employer (2020-2023).
            The base salary range for this job is USD $140,400.00 - USD $372,300.00 /Yr.
            """,
            min: 2020,
            max: 2023
        )])

        let result = try await store.repairStoredSalaries()
        XCTAssertEqual(result.corrected, 1)
        XCTAssertEqual(result.cleared, 0)

        let repaired = try await job(store, 7)
        XCTAssertEqual(repaired.salaryMin, 140_400)
        XCTAssertEqual(repaired.salaryMax, 372_300)
        XCTAssertEqual(repaired.salaryCurrency, "USD")
    }

    /// A hand-edited salary outranks both parsers and is reported rather than silently kept.
    func testManuallyOverriddenSalaryIsUntouched() async throws {
        let store = try await store([makeJob(
            number: 9,
            description: "Best Places to Work (2020-2023).",
            min: 2020,
            max: 2023,
            overrides: #"["salaryMin","salaryMax"]"#
        )])

        let result = try await store.repairStoredSalaries()
        XCTAssertEqual(result.skippedOverridden, 1)
        XCTAssertEqual(result.cleared, 0)

        let untouched = try await job(store, 9)
        XCTAssertEqual(untouched.salaryMin, 2020)
        XCTAssertEqual(untouched.salaryMax, 2023)
    }

    /// A figure the model read out of prose the range regexes can't re-find must survive: both ends
    /// appear as money in the posting, so the evidence supports the stored band.
    func testSupportedBandIsKeptWhenTheParserFindsNoRange() async throws {
        let store = try await store([makeJob(
            number: 11,
            description: "Compensation is $150,000 at hire, rising to $210,000 at senior level.",
            note: "Competitive pay",
            min: 150_000,
            max: 210_000
        )])

        let result = try await store.repairStoredSalaries()
        XCTAssertEqual(result.cleared, 0, "a band the text supports must not be cleared")

        let kept = try await job(store, 11)
        XCTAssertEqual(kept.salaryMin, 150_000)
        XCTAssertEqual(kept.salaryMax, 210_000)
    }

    func testJobsWithNoSalaryAreLeftAlone() async throws {
        let store = try await store([makeJob(
            number: 13,
            description: "We look for 5-7 years of experience.",
            currency: nil
        )])
        let result = try await store.repairStoredSalaries()
        XCTAssertEqual(result.corrected, 0)
        XCTAssertEqual(result.cleared, 0)
    }

    /// The settings-reading entry point the migrator calls works against a store with no settings rows.
    func testSettingsEntryPointRuns() async throws {
        let store = try await store([makeJob(
            number: 17,
            description: "Best Places to Work (2020-2023).",
            min: 2020,
            max: 2023
        )])
        let result = try await store.repairStoredSalariesFromSettings()
        XCTAssertEqual(result.cleared, 1)
    }
}
