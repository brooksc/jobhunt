import SwiftData
import XCTest
@testable import JobhuntCore

/// Tests for `BackgroundStore.backfillBoardLocations` — the one-time restore of board location
/// strings from the snapshot taken before the discovery ledger dropped its `rawJSON` (TASK-693).
///
/// The pins that matter are the ones that keep it a *restore* rather than a re-derivation: it fills
/// only an empty location, never overwrites one that says something, and never touches `remoteType`
/// — inferring an arrangement from a location string is what erased 223 of them in TASK-708.
final class BoardLocationBackfillTests: XCTestCase {
    private typealias Record = BackgroundStore.BoardLocationRecord

    private func makeJob(
        number: Int,
        url: String,
        location: String? = nil,
        remoteType: RemoteType? = nil
    ) -> (Job, Capture) {
        let job = Job(jobNumber: number, title: "Product Manager")
        job.location = location
        job.remoteType = remoteType
        let capture = Capture(url: url, pageTitle: "Product Manager", rawHash: "hash-\(number)")
        job.capture = capture
        return (job, capture)
    }

    private func store(_ rows: [(Job, Capture)]) async throws -> BackgroundStore {
        let store = try BackgroundStore(modelContainer: ModelContainerFactory.inMemory())
        try await store.insertBatch(rows.map(\.0))
        try await store.insertBatch(rows.map(\.1))
        return store
    }

    private func job(_ store: BackgroundStore, _ number: Int) async throws -> Job {
        let rows = try await store.fetch(
            FetchDescriptor<Job>(predicate: #Predicate { $0.jobNumber == number })
        )
        return try XCTUnwrap(rows.first)
    }

    private func dedupKey(_ url: String) throws -> String {
        try XCTUnwrap(DiscoveredPosting.dedupKey(for: url))
    }

    // MARK: - Filling

    func testFillsAnEmptyLocationMatchedByDedupKey() async throws {
        let url = "https://boards.greenhouse.io/acme/jobs/4242"
        let store = try await store([makeJob(number: 1, url: url, location: nil)])
        let record = try Record(dedupKey: dedupKey(url), url: url, locationRaw: "United States")

        let summary = try await store.backfillBoardLocations(from: [record])

        XCTAssertEqual(summary.recordsRead, 1)
        XCTAssertEqual(summary.matchedByDedupKey, 1)
        XCTAssertEqual(summary.matchedByURL, 0)
        XCTAssertEqual(summary.filled, 1)
        XCTAssertEqual(summary.unmatched, 0)
        let filled = try await job(store, 1)
        XCTAssertEqual(filled.location, "United States")
    }

    /// A whitespace-only location is as empty as nil — the board's value should still land.
    func testTreatsWhitespaceOnlyLocationAsEmpty() async throws {
        let url = "https://boards.greenhouse.io/acme/jobs/1"
        let store = try await store([makeJob(number: 1, url: url, location: "   ")])

        let summary = try await store.backfillBoardLocations(
            from: [Record(dedupKey: dedupKey(url), url: url, locationRaw: "Remote - US")]
        )

        XCTAssertEqual(summary.filled, 1)
        let updated = try await job(store, 1)
        XCTAssertEqual(updated.location, "Remote - US")
    }

    // MARK: - Never overwriting

    func testLeavesAPopulatedLocationAlone() async throws {
        let url = "https://boards.greenhouse.io/acme/jobs/7"
        let store = try await store([makeJob(number: 1, url: url, location: "San Jose, CA")])

        let summary = try await store.backfillBoardLocations(
            from: [Record(dedupKey: dedupKey(url), url: url, locationRaw: "United States")]
        )

        XCTAssertEqual(summary.matchedByDedupKey, 1)
        XCTAssertEqual(summary.filled, 0)
        XCTAssertEqual(summary.skippedAlreadyPopulated, 1)
        let untouched = try await job(store, 1)
        XCTAssertEqual(untouched.location, "San Jose, CA")
    }

    // MARK: - URL fallback

    func testMatchesByURLWhenTheDedupKeyMisses() async throws {
        let url = "https://acme.example.com/careers/42"
        let store = try await store([makeJob(number: 1, url: url)])
        // A key from a board that keyed this posting differently, plus the same URL wearing a
        // tracking parameter — the case the URL fallback exists for.
        let record = Record(
            dedupKey: "greenhouse:acme:999999",
            url: url + "?utm_source=alerts",
            locationRaw: "Tokyo, Japan"
        )

        let summary = try await store.backfillBoardLocations(from: [record])

        XCTAssertEqual(summary.matchedByDedupKey, 0)
        XCTAssertEqual(summary.matchedByURL, 1)
        XCTAssertEqual(summary.filled, 1)
        let updated = try await job(store, 1)
        XCTAssertEqual(updated.location, "Tokyo, Japan")
    }

    func testCountsARecordWithNoJobAsUnmatched() async throws {
        let store = try await store([makeJob(number: 1, url: "https://boards.greenhouse.io/acme/jobs/1")])

        let summary = try await store.backfillBoardLocations(from: [
            Record(
                dedupKey: "greenhouse:other:5",
                url: "https://boards.greenhouse.io/other/jobs/5",
                locationRaw: "Berlin"
            )
        ])

        XCTAssertEqual(summary.unmatched, 1)
        XCTAssertEqual(summary.filled, 0)
    }

    // MARK: - Idempotence

    func testASecondRunChangesNothing() async throws {
        let url = "https://boards.greenhouse.io/acme/jobs/9"
        let store = try await store([makeJob(number: 1, url: url)])
        let records = try [Record(dedupKey: dedupKey(url), url: url, locationRaw: "United States")]

        let first = try await store.backfillBoardLocations(from: records)
        let second = try await store.backfillBoardLocations(from: records)

        XCTAssertEqual(first.filled, 1)
        XCTAssertEqual(second.filled, 0)
        XCTAssertEqual(second.skippedAlreadyPopulated, 1)
        let updated = try await job(store, 1)
        XCTAssertEqual(updated.location, "United States")
    }

    // MARK: - Work arrangements are not this pass's business

    /// The whole point of the narrow scope: "Remote" in a board's location field is location text,
    /// not a verdict on the work arrangement. A nil `remoteType` must stay nil.
    func testNeverSetsRemoteType() async throws {
        let remoteURL = "https://boards.greenhouse.io/acme/jobs/10"
        let onsiteURL = "https://boards.greenhouse.io/acme/jobs/11"
        let store = try await store([
            makeJob(number: 1, url: remoteURL, remoteType: nil),
            makeJob(number: 2, url: onsiteURL, remoteType: .onsite)
        ])

        let summary = try await store.backfillBoardLocations(from: [
            Record(dedupKey: dedupKey(remoteURL), url: remoteURL, locationRaw: "Remote - United States"),
            Record(dedupKey: dedupKey(onsiteURL), url: onsiteURL, locationRaw: "Remote")
        ])

        XCTAssertEqual(summary.filled, 2)
        let stillUnknown = try await job(store, 1)
        XCTAssertNil(stillUnknown.remoteType)
        let stillOnsite = try await job(store, 2)
        XCTAssertEqual(stillOnsite.remoteType, .onsite)
    }

    // MARK: - Snapshot decoding

    /// The snapshot is a persisted JSON schema, so a row missing a key must degrade to an unusable
    /// record rather than throwing the whole file away.
    func testDecodesRowsWithMissingKeys() throws {
        let json = Data("""
        [{"dedupKey":"ashby:acme:1","sourceID":"ashby","url":"https://jobs.ashbyhq.com/acme/1",
          "title":"PM","locationRaw":"United States"},
         {"dedupKey":"ashby:acme:2"}]
        """.utf8)

        let records = try Record.decode(json)

        XCTAssertEqual(records.count, 2)
        XCTAssertEqual(records[0].locationRaw, "United States")
        XCTAssertNil(records[1].locationRaw)
        XCTAssertNil(records[1].url)
    }

    func testARecordWithNoLocationTextFillsNothing() async throws {
        let url = "https://boards.greenhouse.io/acme/jobs/12"
        let store = try await store([makeJob(number: 1, url: url)])

        let summary = try await store.backfillBoardLocations(
            from: [Record(dedupKey: dedupKey(url), url: url, locationRaw: "  ")]
        )

        XCTAssertEqual(summary.skippedBlankSource, 1)
        XCTAssertEqual(summary.filled, 0)
        let untouched = try await job(store, 1)
        XCTAssertNil(untouched.location)
    }

    // MARK: - Durability

    /// Without recording `boardLocation`, the restore survives only until the job is re-extracted:
    /// the model reads a body that never states a location and the value is lost again. Recording it
    /// is what lets the snapshot file finally be retired.
    func testRecordsBoardLocationSoTheFillSurvivesReExtraction() async throws {
        let url = "https://boards.greenhouse.io/acme/jobs/20"
        let store = try await store([makeJob(number: 1, url: url, location: nil)])

        let summary = try await store.backfillBoardLocations(
            from: [Record(dedupKey: dedupKey(url), url: url, locationRaw: "United States")]
        )

        XCTAssertEqual(summary.filled, 1)
        XCTAssertEqual(summary.boardLocationsRecorded, 1)
        let filled = try await job(store, 1)
        XCTAssertEqual(filled.capture?.boardLocation, "United States")
    }

    /// A capture that already carries the board's answer keeps it — this pass restores lost data, it
    /// does not re-litigate a value the ingest path already recorded.
    func testDoesNotOverwriteAnExistingBoardLocation() async throws {
        let url = "https://boards.greenhouse.io/acme/jobs/21"
        let rows = [makeJob(number: 1, url: url, location: nil)]
        rows[0].1.boardLocation = "Berlin, Germany"
        let store = try await store(rows)

        let summary = try await store.backfillBoardLocations(
            from: [Record(dedupKey: dedupKey(url), url: url, locationRaw: "United States")]
        )

        XCTAssertEqual(summary.filled, 1)
        XCTAssertEqual(summary.boardLocationsRecorded, 0)
        let filled = try await job(store, 1)
        XCTAssertEqual(filled.location, "United States")
        XCTAssertEqual(filled.capture?.boardLocation, "Berlin, Germany")
    }

    /// Scope pin: jobs that already state a location are skipped entirely, so their capture's prompt
    /// input is not rewritten either. Only data this pass restored is made durable.
    func testDoesNotRecordBoardLocationForAnAlreadyPopulatedJob() async throws {
        let url = "https://boards.greenhouse.io/acme/jobs/22"
        let store = try await store([makeJob(number: 1, url: url, location: "Austin, TX")])

        let summary = try await store.backfillBoardLocations(
            from: [Record(dedupKey: dedupKey(url), url: url, locationRaw: "United States")]
        )

        XCTAssertEqual(summary.skippedAlreadyPopulated, 1)
        XCTAssertEqual(summary.filled, 0)
        XCTAssertEqual(summary.boardLocationsRecorded, 0)
        let untouched = try await job(store, 1)
        XCTAssertEqual(untouched.location, "Austin, TX")
        XCTAssertNil(untouched.capture?.boardLocation)
    }
}
