import SwiftData
import XCTest
@testable import JobhuntCore

/// Validates the committed test fixture (`tests/fixtures/jobhunt-test.sqlite`, produced by
/// `scripts/build-fixture-db.sh` from `FixtureSeeder`) and demonstrates the fixture-backed
/// test pattern: open an isolated copy via `ModelContainerFactory.fixture(copying:)` and read
/// it through a `BackgroundStore` (same access path the app and the rest of the suite use).
///
/// The exact counts here are a drift detector — if `FixtureSeeder` changes, rebuild the
/// fixture (`./scripts/build-fixture-db.sh`) and update these expectations deliberately.
final class FixtureTests: XCTestCase {
    // Expected contents of the committed fixture (see docs/test-db-spec.md).
    private enum Expected {
        static let jobs = 48
        static let captures = 48
        static let events = 50
        static let sites = 5
        static let savedSearches = 3
        static let actions = 6
        static let duplicateMarked = 3
        static let jobsByStatus: [String: Int] = [
            "new": 12, "pursuing": 8, "applied": 7, "interview": 3, "offer": 2,
            "rejected": 4, "passed": 3, "archived": 3, "closed": 2, "expired": 4,
        ]
    }

    /// Resolves the committed fixture relative to this source file so it works in any
    /// checkout/CI without hardcoding an absolute path.
    static func fixtureURL() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()          // tests/CoreTests
            .deletingLastPathComponent()          // tests
            .appendingPathComponent("fixtures/jobhunt-test.sqlite")
    }

    private func openFixtureStore() throws -> BackgroundStore {
        let url = Self.fixtureURL()
        try XCTSkipUnless(
            FileManager.default.fileExists(atPath: url.path),
            "Fixture missing — run ./scripts/build-fixture-db.sh"
        )
        let container = try ModelContainerFactory.fixture(copying: url)
        return BackgroundStore(modelContainer: container)
    }

    // MARK: - Validation (drift detector)

    func testFixtureEntityCounts() async throws {
        let store = try openFixtureStore()
        let jobs = try await store.fetch(FetchDescriptor<Job>())
        XCTAssertEqual(jobs.count, Expected.jobs)
        let captures = try await store.fetch(FetchDescriptor<Capture>())
        XCTAssertEqual(captures.count, Expected.captures)
        let events = try await store.fetch(FetchDescriptor<JobEvent>())
        XCTAssertEqual(events.count, Expected.events)
        let sites = try await store.fetch(FetchDescriptor<Site>())
        XCTAssertEqual(sites.count, Expected.sites)
        let searches = try await store.fetch(FetchDescriptor<SavedSearch>())
        XCTAssertEqual(searches.count, Expected.savedSearches)
        let actions = try await store.fetch(FetchDescriptor<JobAction>())
        XCTAssertEqual(actions.count, Expected.actions)
    }

    func testFixtureCoversEveryStatus() async throws {
        let store = try openFixtureStore()
        let jobs = try await store.fetch(FetchDescriptor<Job>())
        let byStatus = Dictionary(grouping: jobs, by: { $0.status.rawValue }).mapValues(\.count)
        for (status, expected) in Expected.jobsByStatus {
            XCTAssertEqual(byStatus[status], expected, "status '\(status)' count drifted")
        }
        // Every JobStatus the seeder targets is represented — guards against a status
        // silently dropping out of the fixture.
        XCTAssertEqual(Set(byStatus.keys), Set(Expected.jobsByStatus.keys))
    }

    func testFixtureHasDuplicateAndExtractionEdgeCases() async throws {
        let store = try openFixtureStore()
        let jobs = try await store.fetch(FetchDescriptor<Job>())

        let dupMarked = jobs.filter { $0.duplicateOfJobID != nil }
        XCTAssertEqual(dupMarked.count, Expected.duplicateMarked)
        // Referential integrity: every duplicate points at a real job in the fixture.
        let ids = Set(jobs.map(\.id))
        for dup in dupMarked {
            XCTAssertTrue(ids.contains(dup.duplicateOfJobID ?? ""), "dangling duplicateOfJobID")
        }

        // Extraction edge cases are present (pending + failed), not just succeeded.
        XCTAssertGreaterThan(jobs.filter { $0.extractionStatus == .pending }.count, 0)
        XCTAssertGreaterThan(jobs.filter { $0.extractionStatus == .failed }.count, 0)
    }

    // MARK: - Fixture-backed read test (demonstrates the pattern over realistic data)

    func testFixtureBackedQuery_pursuingJobs() async throws {
        let store = try openFixtureStore()
        let pursuing = try await store.fetch(FetchDescriptor<Job>()).filter { $0.status == .pursuing }
        XCTAssertEqual(pursuing.count, Expected.jobsByStatus["pursuing"])
    }

    // TASK-420: two fixture copies must be independent — each gets its own temp destination so
    // parallel consumers can't delete or overwrite each other's store.
    func testFixtureCopiesAreIsolatedPerCall() throws {
        let url = Self.fixtureURL()
        try XCTSkipUnless(FileManager.default.fileExists(atPath: url.path),
                          "Fixture missing — run ./scripts/build-fixture-db.sh")
        let a = try ModelContainerFactory.fixture(copying: url)
        let b = try ModelContainerFactory.fixture(copying: url)
        let pathA = a.configurations.first?.url.path
        let pathB = b.configurations.first?.url.path
        XCTAssertNotNil(pathA)
        XCTAssertNotNil(pathB)
        XCTAssertNotEqual(pathA, pathB, "Each fixture copy must use a distinct temp destination")
    }

    // TASK-421: seeding twice yields identical timestamps (fixed base date, no wall-clock drift).
    func testFixtureSeed_isDeterministicAcrossRuns() async throws {
        func seedAndSnapshot() async throws -> [(Int, Date, Date?)] {
            let store = BackgroundStore(modelContainer: try ModelContainerFactory.inMemory())
            try await FixtureSeeder.seed(into: store)
            let jobs = try await store.fetch(FetchDescriptor<Job>(sortBy: [SortDescriptor(\.jobNumber)]))
            return jobs.map { ($0.jobNumber ?? -1, $0.createdAt, $0.capturedAtDenormalized) }
        }
        let runA = try await seedAndSnapshot()
        let runB = try await seedAndSnapshot()
        XCTAssertFalse(runA.isEmpty)
        XCTAssertEqual(runA.count, runB.count)
        for (a, b) in zip(runA, runB) {
            XCTAssertEqual(a.0, b.0)
            XCTAssertEqual(a.1, b.1, "createdAt must be identical across regenerations")
            XCTAssertEqual(a.2, b.2, "capturedAt must be identical across regenerations")
        }
        // And anchored to the documented fixed base date, not wall-clock now.
        XCTAssertLessThan(runA.map(\.1).max()!, Date(timeIntervalSince1970: 1_760_000_000))
    }
}
