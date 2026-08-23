import Foundation
import SwiftData
import XCTest
@testable import JobhuntCore

/// The ledger that stops every sweep re-ingesting the same board (TASK-691, M2).
final class DiscoveryLedgerTests: XCTestCase {
    private func makeStore() throws -> BackgroundStore {
        try BackgroundStore(modelContainer: ModelContainerFactory.inMemory())
    }

    private func posting(
        _ key: String, title: String = "Program Manager", source: String = "greenhouse"
    ) -> DiscoveredPosting {
        DiscoveredPosting(
            dedupKey: key, url: "https://boards.greenhouse.io/acme/jobs/\(key)", title: title,
            company: "Acme", locationRaw: "Remote, United States", sourceID: source
        )
    }

    private let criteria = DiscoveryCriteria(titleIncludeAny: ["program manager"])

    // MARK: - Fingerprint

    /// The reason the ledger stores a SHA and not `hashValue`: Swift seeds `Hashable` per process,
    /// so a persisted `hashValue` would differ on the next launch and invalidate the whole ledger
    /// at every start — re-flooding the ingest cap daily.
    func testTheFingerprintIsStableAcrossInstances() {
        let a = DiscoveryCriteria(titleIncludeAny: ["program manager"], locationBlock: ["india"])
        let b = DiscoveryCriteria(titleIncludeAny: ["program manager"], locationBlock: ["india"])
        XCTAssertEqual(a.fingerprint, b.fingerprint)
        XCTAssertEqual(a.fingerprint.count, 64, "SHA-256, hex")
    }

    func testAnyCriteriaChangeMovesTheFingerprint() {
        var widened = criteria
        widened.titleIncludeAny.append("product manager")
        XCTAssertNotEqual(criteria.fingerprint, widened.fingerprint)
    }

    // MARK: - Skipping known postings

    func testAPostingJudgedUnderTheSameCriteriaIsNotJudgedAgain() async throws {
        let store = try makeStore()
        let seen = posting("1")
        try await store.recordDiscoveryOutcomes(
            [(seen, .rejected, .title)], criteriaFingerprint: criteria.fingerprint
        )
        let unjudged = try await store.unjudgedPostings(
            [seen, posting("2")], criteriaFingerprint: criteria.fingerprint
        )
        XCTAssertEqual(unjudged.map(\.dedupKey), ["2"], "the second sweep only considers what's new")
    }

    /// The other half of storing the fingerprint. A user who adds a keyword must see the rows the
    /// old keywords discarded, or widening the search would silently do nothing.
    func testWideningTheCriteriaReexaminesEverythingRejected() async throws {
        let store = try makeStore()
        try await store.recordDiscoveryOutcomes(
            [(posting("1"), .rejected, .title)], criteriaFingerprint: criteria.fingerprint
        )
        var widened = criteria
        widened.titleIncludeAny.append("product manager")

        let unjudged = try await store.unjudgedPostings(
            [posting("1")], criteriaFingerprint: widened.fingerprint
        )
        XCTAssertEqual(unjudged.count, 1)
    }

    /// …but an ingested posting stays ingested. Re-ingesting it because the criteria widened would
    /// resurrect a job the user has since archived.
    func testAnIngestedPostingIsNeverReconsidered() async throws {
        let store = try makeStore()
        try await store.recordDiscoveryOutcomes(
            [(posting("1"), .ingested, nil)], criteriaFingerprint: criteria.fingerprint
        )
        var widened = criteria
        widened.titleIncludeAny.append("product manager")

        let unjudged = try await store.unjudgedPostings(
            [posting("1")], criteriaFingerprint: widened.fingerprint
        )
        XCTAssertTrue(unjudged.isEmpty)
    }

    /// A hydration failure was the network's fault, not the posting's, so it is retried even when
    /// nothing about the criteria changed.
    func testAHydrationFailureIsRetriedWithoutACriteriaChange() async throws {
        let store = try makeStore()
        try await store.recordDiscoveryOutcomes(
            [(posting("1"), .hydrationFailed, nil)], criteriaFingerprint: criteria.fingerprint
        )
        let unjudged = try await store.unjudgedPostings(
            [posting("1")], criteriaFingerprint: criteria.fingerprint
        )
        XCTAssertEqual(unjudged.count, 1)
    }

    // MARK: - Recording

    func testRecordingTwiceUpdatesRatherThanDuplicating() async throws {
        let store = try makeStore()
        try await store.recordDiscoveryOutcomes(
            [(posting("1"), .rejected, .title)], criteriaFingerprint: criteria.fingerprint
        )
        try await store.recordDiscoveryOutcomes(
            [(posting("1"), .ingested, nil)], criteriaFingerprint: criteria.fingerprint
        )
        let counts = try await store.discoveryOutcomeCounts()
        XCTAssertEqual(counts["ingested"], 1)
        XCTAssertNil(counts["rejected.title"], "the row was updated, not duplicated")
    }

    /// A board that lists the same posting under two URLs in one payload would otherwise violate
    /// the unique constraint mid-batch and lose the whole sweep.
    func testTheSameKeyTwiceInOneBatchDoesNotThrow() async throws {
        let store = try makeStore()
        try await store.recordDiscoveryOutcomes(
            [(posting("1"), .rejected, .title), (posting("1"), .rejected, .location)],
            criteriaFingerprint: criteria.fingerprint
        )
        let counts = try await store.discoveryOutcomeCounts()
        XCTAssertEqual(counts.values.reduce(0, +), 1)
    }

    func testTheHistogramSeparatesRejectionReasons() async throws {
        let store = try makeStore()
        try await store.recordDiscoveryOutcomes([
            (posting("1"), .rejected, .title),
            (posting("2"), .rejected, .title),
            (posting("3"), .rejected, .location),
            (posting("4"), .ingested, nil)
        ], criteriaFingerprint: criteria.fingerprint)

        let counts = try await store.discoveryOutcomeCounts()
        XCTAssertEqual(counts["rejected.title"], 2)
        XCTAssertEqual(counts["rejected.location"], 1)
        XCTAssertEqual(counts["ingested"], 1)
    }

    // MARK: - Retained raw rows

    func testRawRowsSurviveARoundTripForThePreview() async throws {
        let store = try makeStore()
        let original = DiscoveredPosting(
            dedupKey: "gh:9", url: "https://boards.greenhouse.io/acme/jobs/9",
            title: "Program Manager", company: "Acme", locationRaw: "Remote, US",
            firstPublished: Date(timeIntervalSince1970: 1_800_000_000),
            salaryMinPublished: 150_000, descriptionPlain: "Body.", sourceID: "greenhouse"
        )
        try await store.recordDiscoveryOutcomes(
            [(original, .rejected, .title)], criteriaFingerprint: criteria.fingerprint
        )
        let restored = try await store.retainedRawPostings()
        XCTAssertEqual(restored.count, 1)
        XCTAssertEqual(restored.first, original, "the preview replays gate A over these")
    }

    /// One sweep's payloads per source: enough for the preview, not a copy of every board the user
    /// has ever pointed at. The keys stay, because forgetting one means re-ingesting a job.
    func testClearingRetainedRowsKeepsTheKeys() async throws {
        let store = try makeStore()
        try await store.recordDiscoveryOutcomes(
            [(posting("1"), .rejected, .title)], criteriaFingerprint: criteria.fingerprint
        )
        let cleared = try await store.clearRetainedRawRows(sourceID: "greenhouse")
        XCTAssertEqual(cleared, 1)
        let retained: [DiscoveredPosting] = try await store.retainedRawPostings()
        XCTAssertTrue(retained.isEmpty)

        let unjudged = try await store.unjudgedPostings(
            [posting("1")], criteriaFingerprint: criteria.fingerprint
        )
        XCTAssertTrue(unjudged.isEmpty, "the posting is still known even though its payload is gone")
    }

    func testClearingIsScopedToOneSource() async throws {
        let store = try makeStore()
        try await store.recordDiscoveryOutcomes([
            (posting("1", source: "greenhouse"), .rejected, .title),
            (posting("2", source: "lever"), .rejected, .title)
        ], criteriaFingerprint: criteria.fingerprint)

        try await store.clearRetainedRawRows(sourceID: "greenhouse")
        let remaining = try await store.retainedRawPostings()
        XCTAssertEqual(remaining.map(\.sourceID), ["lever"])
    }

    func testAnEmptySweepIsANoOp() async throws {
        let store = try makeStore()
        try await store.recordDiscoveryOutcomes([], criteriaFingerprint: criteria.fingerprint)
        let unjudged: [DiscoveredPosting] = try await store.unjudgedPostings(
            [], criteriaFingerprint: criteria.fingerprint
        )
        let counts: [String: Int] = try await store.discoveryOutcomeCounts()
        XCTAssertTrue(unjudged.isEmpty)
        XCTAssertTrue(counts.isEmpty)
    }
}
