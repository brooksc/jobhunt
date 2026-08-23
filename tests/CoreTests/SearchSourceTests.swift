import Foundation
import SwiftData
import XCTest
@testable import JobhuntCore

/// One board jobhunt sweeps on a schedule (TASK-692, M3).
///
/// Most of this is scheduling and health bookkeeping, and the health half matters more than it
/// looks: a board that migrates ATS doesn't error, it answers 200 with nothing, forever. The
/// counters here are the only thing that can notice.
final class SearchSourceTests: XCTestCase {
    private func source(
        kind: String = "greenhouse", interval: Int = 12, enabled: Bool = true, created: Date = Date()
    ) -> SearchSource {
        SearchSource(
            kind: kind, label: "Acme", config: SourceConfig(slug: "acme", company: "Acme"),
            enabled: enabled, intervalHours: interval, createdAt: created
        )
    }

    // MARK: - Scheduling

    /// A source the user just added should produce something without them wondering whether it
    /// worked, so it's due the moment it exists.
    func testANewSourceIsDueImmediately() {
        let now = Date()
        XCTAssertTrue(source(created: now).isDue(now: now))
    }

    func testASourceIsNotDueAgainUntilItsIntervalElapses() {
        let now = Date()
        let searchSource = source(interval: 12, created: now)
        searchSource.recordRun(status: .ok, found: 10, passed: 1, ingested: 1, now: now)

        XCTAssertFalse(searchSource.isDue(now: now.addingTimeInterval(11 * 3600)))
        XCTAssertTrue(searchSource.isDue(now: now.addingTimeInterval(13 * 3600)))
    }

    /// Both the per-source toggle and the global one have to stop all activity within a cycle.
    /// Enforcing it here means no caller can forget.
    func testADisabledSourceIsNeverDue() {
        let now = Date()
        XCTAssertFalse(source(enabled: false, created: now.addingTimeInterval(-999_999)).isDue(now: now))
    }

    /// A zero or negative interval would schedule the next run in the past and spin.
    func testAnAbsurdIntervalStillSchedulesForward() {
        let now = Date()
        let searchSource = source(interval: 0, created: now)
        searchSource.recordRun(status: .ok, now: now)
        let next = try? XCTUnwrap(searchSource.nextRunAt)
        XCTAssertGreaterThan(next ?? now, now)
    }

    // MARK: - Health

    /// The counter that catches a silent migration. Three empty runs in a row isn't proof, but it's
    /// the point at which saying something beats continuing to say nothing.
    func testConsecutiveEmptyRunsAccumulateUntilSomethingIsFound() {
        let searchSource = source()
        XCTAssertFalse(searchSource.looksMigrated)

        for _ in 1 ... 3 {
            searchSource.recordRun(status: .empty)
        }
        XCTAssertEqual(searchSource.consecutiveEmptyRuns, 3)
        XCTAssertTrue(searchSource.looksMigrated)

        searchSource.recordRun(status: .ok, found: 12, passed: 1, ingested: 1)
        XCTAssertEqual(searchSource.consecutiveEmptyRuns, 0)
        XCTAssertFalse(searchSource.looksMigrated)
    }

    /// A rate limit says nothing about whether the board moved, so it must not accumulate toward
    /// the migration signal — otherwise a flaky week would read as a dead board.
    func testATruncatedRunDoesNotCountAsEmpty() {
        let searchSource = source()
        searchSource.recordRun(status: .empty)
        searchSource.recordRun(status: .truncated, found: 40)
        XCTAssertEqual(searchSource.consecutiveEmptyRuns, 0)
    }

    /// `empty` is a *successful* run, but it's the one worth watching. `ok` and `never` are the
    /// only two states that need nothing from the user.
    func testOnlyHealthyStatesAskNothingOfTheUser() {
        XCTAssertFalse(SearchSourceStatus.ok.needsAttention)
        XCTAssertFalse(SearchSourceStatus.never.needsAttention)
        for status in [SearchSourceStatus.empty, .truncated, .unreachable, .rateLimited, .misconfigured] {
            XCTAssertTrue(status.needsAttention, status.rawValue)
        }
    }

    func testARunRecordsWhatItFoundForTheUIToShow() {
        let searchSource = source()
        searchSource.recordRun(status: .ok, found: 6168, passed: 41, ingested: 12)
        XCTAssertEqual(searchSource.lastFoundCount, 6168)
        XCTAssertEqual(searchSource.lastPassedCount, 41)
        XCTAssertEqual(searchSource.lastIngestedCount, 12)
        XCTAssertNotNil(searchSource.lastRunAt)
    }

    func testAFailureKeepsItsMessageAndAnySuccessClearsIt() {
        let searchSource = source()
        searchSource.recordRun(status: .unreachable, error: "HTTP 503 from boards-api.greenhouse.io")
        XCTAssertEqual(searchSource.lastError, "HTTP 503 from boards-api.greenhouse.io")
        searchSource.recordRun(status: .ok, found: 1)
        XCTAssertNil(searchSource.lastError, "a stale error next to a healthy dot reads as a live problem")
    }

    // MARK: - Config

    func testTheConfigSurvivesARoundTripThroughStorage() {
        let searchSource = source()
        XCTAssertEqual(searchSource.config.slug, "acme")
        XCTAssertEqual(searchSource.config.company, "Acme")

        searchSource.config = SourceConfig(slug: "https://acme.wd5.myworkdayjobs.com/careers")
        XCTAssertEqual(searchSource.config.slug, "https://acme.wd5.myworkdayjobs.com/careers")
        XCTAssertNil(searchSource.config.company)
    }

    /// A config that can't be read must not crash a sweep — it degrades to an empty slug, which the
    /// source then reports as `misconfigured`.
    func testAnUnreadableConfigDegradesRatherThanCrashing() {
        let searchSource = source()
        searchSource.configJSON = "not json"
        XCTAssertEqual(searchSource.config.slug, "")
    }

    func testTheKindResolvesToARealSource() {
        XCTAssertEqual(source(kind: "greenhouse").source?.displayName, "Greenhouse")
        XCTAssertEqual(source(kind: "workday").source?.displayName, "Workday")
        XCTAssertNil(source(kind: "myspace").source)
    }

    // MARK: - Persistence

    func testASourceRoundTripsThroughTheStore() async throws {
        let store = try BackgroundStore(modelContainer: ModelContainerFactory.inMemory())
        let searchSource = source()
        try await store.insert(searchSource)

        let fetched: [SearchSource] = try await store.fetch(FetchDescriptor<SearchSource>())
        XCTAssertEqual(fetched.count, 1)
        XCTAssertEqual(fetched.first?.label, "Acme")
        XCTAssertEqual(fetched.first?.status, .never)
    }
}
