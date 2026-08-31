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

    /// This is a repair, not a bulk re-extraction: a job with no salary must not be given one, even
    /// when the posting plainly states a band. Filling those in silently overrides what the
    /// extraction pipeline decided for rows nobody asked us to touch.
    func testSalaryIsNeverFilledInOnAJobThatHasNone() async throws {
        let store = try await store([makeJob(
            number: 21,
            description: "The base salary range for this job is USD $184,000 - USD $230,000 /Yr.",
            currency: nil
        )])
        let result = try await store.repairStoredSalaries()
        XCTAssertEqual(result.corrected, 0)
        XCTAssertEqual(result.cleared, 0)

        let untouched = try await job(store, 21)
        XCTAssertNil(untouched.salaryMin)
        XCTAssertNil(untouched.salaryMax)
    }

    /// A stored band the evidence supports is left alone even where re-parsing would pick a different
    /// band (here the location-specific one) — that is re-extraction, not repair of an invented band.
    func testSupportedBandIsNotRebandedToADifferentRange() async throws {
        let store = try await store([makeJob(
            number: 23,
            description: """
            San Francisco Bay Area: 133,400 - 226,600 USD Annual
            All Other US Locations: 116,000 - 197,000 USD Annual
            """,
            min: 116_000,
            max: 197_000
        )])
        let result = try await store.repairStoredSalaries(preferredLocations: "San Francisco, CA")
        XCTAssertEqual(result.corrected, 0)

        let kept = try await job(store, 23)
        XCTAssertEqual(kept.salaryMin, 116_000)
        XCTAssertEqual(kept.salaryMax, 197_000)
    }

    /// The five bands an earlier cut of this repair deleted: no currency marker anywhere, so nothing
    /// the money parser reads — but the figures are stated in the note, and re-parsing finds them.
    func testDecimalAndBareNotesKeepTheirBands() async throws {
        let store = try await store([
            makeJob(
                number: 1027, description: "Salary information.",
                note: "100,000.00 - 170,500.00 annually", min: 100_000, max: 170_500
            ),
            makeJob(
                number: 451, description: "Salary information.",
                note: "103,500 - 181,000", min: 103_500, max: 181_000
            )
        ])
        let result = try await store.repairStoredSalaries()
        XCTAssertEqual(result.cleared, 0, "a stated band must never be cleared")
        XCTAssertEqual(result.corrected, 0)

        let first = try await job(store, 1027)
        XCTAssertEqual(first.salaryMin, 100_000)
        XCTAssertEqual(first.salaryMax, 170_500)
        let second = try await job(store, 451)
        XCTAssertEqual(second.salaryMin, 103_500)
        XCTAssertEqual(second.salaryMax, 181_000)
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

    // MARK: - Ways a stored figure is accounted for (all three were needed by the real store)

    /// `moneyAmounts` reads only $/€/£ and USD/CAD/EUR/GBP, so a rupee or krona band looks like an
    /// unrecognised number. The digits are right there in the note, which is a statement of pay.
    func testForeignCurrencyNotesAreNotCleared() async throws {
        let sek = "In Sweden, the base compensation range for this role is SEK 996,819 - SEK 1,196,182"
        let store = try await store([
            makeJob(
                number: 412, description: "Job body.", note: "₹40,50,000 – ₹56,70,000 INR Annually",
                min: 4_050_000, max: 5_670_000, currency: nil
            ),
            makeJob(
                number: 1349, description: "Job body.", note: sek,
                min: 996_819, max: 1_196_182, currency: nil
            )
        ])
        let result = try await store.repairStoredSalaries()
        XCTAssertEqual(result.cleared, 0)
        XCTAssertEqual(result.corrected, 0)
    }

    /// Providence posts per-location hourly bands; the stored annual is the rate × 2080 and appears
    /// nowhere in the text as a literal.
    func testAnnualizedHourlyBandIsNotCleared() async throws {
        let store = try await store([makeJob(
            number: 273,
            description: "Job body.",
            note: "AK: Anchorage: Min: $39.81, Max: $96.35 per hour",
            min: 82805,
            max: 200_408
        )])
        let result = try await store.repairStoredSalaries()
        XCTAssertEqual(result.cleared, 0, "39.81 × 2080 = 82,805 — the same annualization")
    }

    /// Job #128: "401k with employer match" read as a $401,000 salary. No note, and the retirement
    /// token is stripped before money parsing, so nothing accounts for it.
    func testRetirementPlanBandIsCleared() async throws {
        let store = try await store([makeJob(
            number: 128,
            description: "Benefits include 401k with employer match and unlimited PTO.",
            min: 401_000,
            max: 401_000
        )])
        let result = try await store.repairStoredSalaries()
        XCTAssertEqual(result.cleared, 1)

        let repaired = try await job(store, 128)
        XCTAssertNil(repaired.salaryMin)
    }
}
