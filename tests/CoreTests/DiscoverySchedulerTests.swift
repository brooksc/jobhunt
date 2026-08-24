import Foundation
import SwiftData
import XCTest
@testable import JobhuntCore

/// Choosing what to sweep, and the settings that decide how (TASK-692, M3).
final class DiscoverySchedulerTests: XCTestCase {
    private func makeSettings() throws -> SettingsStore {
        try SettingsStore(modelContext: ModelContext(ModelContainerFactory.inMemory()))
    }

    // MARK: - Criteria from settings

    func testCriteriaAreReadFromTheirOwnKeys() throws {
        let settings = try makeSettings()
        try settings.set("program manager, product manager", forKey: SettingsKey.discoveryTitleInclude)
        try settings.set("intern, junior", forKey: SettingsKey.discoveryTitleExclude)
        try settings.set("united states", forKey: SettingsKey.discoveryLocationAllow)
        settings.setInt(150_000, forKey: SettingsKey.discoveryMinSalary)
        settings.setInt(14, forKey: SettingsKey.discoveryMaxAgeDays)

        let criteria = DiscoverySettings.criteria(from: settings)
        XCTAssertEqual(criteria.titleIncludeAny, ["program manager", "product manager"])
        XCTAssertEqual(criteria.titleExcludeAny, ["intern", "junior"])
        XCTAssertEqual(criteria.locationAllow, ["united states"])
        XCTAssertEqual(criteria.minSalaryIfPublished, 150_000)
        XCTAssertEqual(criteria.maxAgeDays, 14)
    }

    /// One stray trailing comma would otherwise put an empty keyword in the list, and an empty
    /// keyword matches every string — silently turning a block list into a no-op.
    func testBlankEntriesAreDroppedRatherThanMatchingEverything() {
        XCTAssertEqual(DiscoverySettings.list("a, , b,,"), ["a", "b"])
        XCTAssertTrue(DiscoverySettings.list("  ,  ").isEmpty)
    }

    // MARK: - Seeding

    /// The user should recognise their own configuration rather than face a blank form.
    func testSeedingCopiesTheExistingRequirementSettings() throws {
        let settings = try makeSettings()
        try settings.set("Seattle, WA", forKey: SettingsKey.preferredLocations)
        try settings.set("United States", forKey: SettingsKey.remoteEligibilityRegions)
        settings.setInt(180_000, forKey: SettingsKey.minSalary)

        XCTAssertTrue(DiscoverySettings.seedIfNeeded(settings))
        let criteria = DiscoverySettings.criteria(from: settings)
        XCTAssertEqual(criteria.locationAllow, ["Seattle", "WA"])
        XCTAssertEqual(criteria.locationAlwaysAllow, ["United States"])
        XCTAssertEqual(criteria.minSalaryIfPublished, 180_000)
    }

    /// It seeds; it does not alias. After seeding, changing the discovery criteria must not touch
    /// the keys that badge every existing job in the app.
    func testSeedingDoesNotAliasTheRequirementSettings() throws {
        let settings = try makeSettings()
        try settings.set("Seattle, WA", forKey: SettingsKey.preferredLocations)
        DiscoverySettings.seedIfNeeded(settings)

        try settings.set("Anywhere", forKey: SettingsKey.discoveryLocationAllow)
        XCTAssertEqual(
            settings.string(forKey: SettingsKey.preferredLocations), "Seattle, WA",
            "widening the search must not re-badge every existing job"
        )
    }

    /// A user who deliberately empties a list must not have it refilled on the next launch.
    func testSeedingHappensOnlyOnce() throws {
        let settings = try makeSettings()
        try settings.set("Seattle, WA", forKey: SettingsKey.preferredLocations)
        XCTAssertTrue(DiscoverySettings.seedIfNeeded(settings))

        try settings.set("", forKey: SettingsKey.discoveryLocationAllow)
        XCTAssertFalse(DiscoverySettings.seedIfNeeded(settings))
        XCTAssertEqual(settings.string(forKey: SettingsKey.discoveryLocationAllow), "")
    }

    /// Seeding deliberately leaves title keywords empty — there is nothing in the existing settings
    /// to derive them from. Onboarding asks for them instead, and `canSweep` holds the feature
    /// closed until it has an answer (see DiscoveryInterlockTests).
    func testSeedingLeavesTitleKeywordsForOnboardingToAsk() throws {
        let settings = try makeSettings()
        DiscoverySettings.seedIfNeeded(settings)
        XCTAssertTrue(DiscoverySettings.criteria(from: settings).titleIncludeAny.isEmpty)
        XCTAssertFalse(DiscoverySettings.canSweep(settings))
    }

    // MARK: - Daily budget

    func testTheDailyBudgetDrainsAsIngestsAreRecorded() throws {
        let settings = try makeSettings()
        settings.setInt(10, forKey: SettingsKey.discoveryMaxIngestsPerDay)
        let now = Date()

        XCTAssertEqual(DiscoverySettings.remainingDailyBudget(settings, now: now), 10)
        DiscoverySettings.recordIngests(4, settings: settings, now: now)
        XCTAssertEqual(DiscoverySettings.remainingDailyBudget(settings, now: now), 6)
        DiscoverySettings.recordIngests(6, settings: settings, now: now)
        XCTAssertEqual(DiscoverySettings.remainingDailyBudget(settings, now: now), 0)
    }

    /// A machine asleep for a week must start fresh rather than believing it has already spent
    /// today's budget.
    func testAStaleDayResetsTheCounter() throws {
        let settings = try makeSettings()
        settings.setInt(10, forKey: SettingsKey.discoveryMaxIngestsPerDay)
        let today = Date()
        DiscoverySettings.recordIngests(10, settings: settings, now: today)
        XCTAssertEqual(DiscoverySettings.remainingDailyBudget(settings, now: today), 0)

        let tomorrow = today.addingTimeInterval(7 * 86400)
        XCTAssertEqual(DiscoverySettings.remainingDailyBudget(settings, now: tomorrow), 10)
    }

    /// Held in settings rather than counted from the ledger, because a job the user deleted must not
    /// hand the sweeper its budget back.
    func testTheBudgetNeverGoesNegative() throws {
        let settings = try makeSettings()
        settings.setInt(2, forKey: SettingsKey.discoveryMaxIngestsPerDay)
        DiscoverySettings.recordIngests(9, settings: settings)
        XCTAssertEqual(DiscoverySettings.remainingDailyBudget(settings), 0)
    }

    // MARK: - Picking a source

    func testTheLongestWaitingSourceGoesFirst() async throws {
        let store = try BackgroundStore(modelContainer: ModelContainerFactory.inMemory())
        let now = Date()
        let fresh = SearchSource(
            kind: "greenhouse", label: "Fresh", config: SourceConfig(slug: "a"),
            createdAt: now.addingTimeInterval(-60)
        )
        let stale = SearchSource(
            kind: "greenhouse", label: "Stale", config: SourceConfig(slug: "b"),
            createdAt: now.addingTimeInterval(-86400)
        )
        try await store.insert(fresh)
        try await store.insert(stale)

        let due: [SearchSource] = try await store.dueSearchSources(now: now)
        XCTAssertEqual(
            due.first?.label, "Stale",
            "without the sort, whichever row was inserted first would be swept every cycle"
        )
    }

    func testADisabledSourceIsNeverDue() async throws {
        let store = try BackgroundStore(modelContainer: ModelContainerFactory.inMemory())
        try await store.insert(SearchSource(
            kind: "greenhouse", label: "Off", config: SourceConfig(slug: "a"), enabled: false
        ))
        let due: [SearchSource] = try await store.dueSearchSources()
        XCTAssertTrue(due.isEmpty)
    }

    /// A failed run still waits its interval. Without moving the clock, an unreachable board would
    /// be retried on every single cycle.
    func testAFailedRunStillAdvancesTheClock() async throws {
        let store = try BackgroundStore(modelContainer: ModelContainerFactory.inMemory())
        let source = SearchSource(kind: "greenhouse", label: "A", config: SourceConfig(slug: "a"))
        try await store.insert(source)
        let now = Date()

        try await store.recordSearchSourceRun(
            id: source.id, status: .unreachable, error: "HTTP 503", now: now
        )
        let due: [SearchSource] = try await store.dueSearchSources(now: now)
        XCTAssertTrue(due.isEmpty)
    }

    // MARK: - CRUD

    func testSourcesCanBeAddedToggledMadeDueAndDeleted() async throws {
        let store = try BackgroundStore(modelContainer: ModelContainerFactory.inMemory())
        let id = try await store.addSearchSource(
            kind: "greenhouse", label: "Acme", config: SourceConfig(slug: "acme")
        )
        try await store.recordSearchSourceRun(id: id, status: .ok, found: 5)
        let afterRun: [SearchSource] = try await store.dueSearchSources()
        XCTAssertTrue(afterRun.isEmpty)

        try await store.markSearchSourceDue(id: id)
        let afterMark: [SearchSource] = try await store.dueSearchSources()
        XCTAssertEqual(afterMark.count, 1, "Run now makes it due without waiting for the interval")

        try await store.setSearchSourceEnabled(id: id, enabled: false)
        let afterDisable: [SearchSource] = try await store.dueSearchSources()
        XCTAssertTrue(afterDisable.isEmpty)

        try await store.deleteSearchSource(id: id)
        let remaining: [SearchSource] = try await store.searchSources()
        XCTAssertTrue(remaining.isEmpty)
    }

    /// A `kind` this build doesn't know — a downgrade, or a source added by a newer version — must
    /// be recorded and have its clock moved on, not retried every cycle forever.
    func testAnUnknownSourceKindIsRecordedRatherThanRetriedForever() async throws {
        let store = try BackgroundStore(modelContainer: ModelContainerFactory.inMemory())
        let queue = QueueActor(
            store: store, isPaused: { true }, onSetPaused: { _ in },
            readExtractionSettings: { ExtractionSettings(
                llmModel: "", preferredLocations: "", locationFilterEnabled: false,
                locationAllowRemote: true, locationAllowHybrid: true, locationAllowOnsite: true
            ) },
            providerFactory: { SchedulerNoOpProvider() }
        )
        let scheduler = DiscoveryScheduler(
            store: store,
            sweeper: DiscoverySweeper(store: store, jobService: JobService(store: store, queue: queue))
        )
        try await store.insert(SearchSource(
            kind: "vendor-from-the-future", label: "Future", config: SourceConfig(slug: "x")
        ))

        let result = await scheduler.runOneDueSweep(
            criteria: DiscoveryCriteria(titleIncludeAny: ["x"]), remainingDailyBudget: 10,
            alreadyCaptured: []
        )
        XCTAssertEqual(result?.status, .misconfigured)
        let due: [SearchSource] = try await store.dueSearchSources()
        XCTAssertTrue(due.isEmpty, "the clock moved on, so it won't be retried next cycle")
    }

    func testNothingDueMeansNoSweep() async throws {
        let store = try BackgroundStore(modelContainer: ModelContainerFactory.inMemory())
        let queue = QueueActor(
            store: store, isPaused: { true }, onSetPaused: { _ in },
            readExtractionSettings: { ExtractionSettings(
                llmModel: "", preferredLocations: "", locationFilterEnabled: false,
                locationAllowRemote: true, locationAllowHybrid: true, locationAllowOnsite: true
            ) },
            providerFactory: { SchedulerNoOpProvider() }
        )
        let scheduler = DiscoveryScheduler(
            store: store,
            sweeper: DiscoverySweeper(store: store, jobService: JobService(store: store, queue: queue))
        )
        let result = await scheduler.runOneDueSweep(
            criteria: DiscoveryCriteria(), remainingDailyBudget: 10, alreadyCaptured: []
        )
        XCTAssertNil(result)
    }
}

private struct SchedulerNoOpProvider: LLMProvider {
    let id: String = "noop"
    let concurrencyLimit: Int = 1
    func complete(_: ChatRequest) async throws -> ChatResponse {
        throw LLMProviderError.httpError(statusCode: 503, body: "no-op")
    }
}

/// The interlock that lets automatic search and the market sweep ship enabled (TASK-697).
///
/// A key feature hidden behind a settings toggle is a feature most users never find, so both are on
/// by default. What makes that safe is not a toggle but this check: an empty title list matches
/// every posting on every board, so nothing sweeps until at least one title exists.
final class DiscoveryInterlockTests: XCTestCase {
    private func makeSettings() throws -> SettingsStore {
        try SettingsStore(modelContext: ModelContext(ModelContainerFactory.inMemory()))
    }

    func testBothFeaturesAreOnByDefault() throws {
        let settings = try makeSettings()
        XCTAssertTrue(
            settings.bool(forKey: SettingsKey.discoveryEnabled),
            "a feature behind a settings toggle is one most users never find"
        )
        XCTAssertTrue(settings.bool(forKey: SettingsKey.marketSweepEnabled))
    }

    /// …and neither actually runs until the one question onboarding asks has an answer.
    func testNothingSweepsWithoutATitleKeyword() throws {
        let settings = try makeSettings()
        XCTAssertTrue(DiscoverySettings.list(
            settings.string(forKey: SettingsKey.discoveryTitleInclude)
        ).isEmpty)
        XCTAssertFalse(
            DiscoverySettings.canSweep(settings),
            "an empty include list matches everything — sweeping on it would spend the whole daily "
                + "cap on arbitrary jobs"
        )
    }

    func testOneTitleKeywordIsEnoughToStart() throws {
        let settings = try makeSettings()
        try settings.set("Product Manager", forKey: SettingsKey.discoveryTitleInclude)
        XCTAssertTrue(DiscoverySettings.canSweep(settings))
    }

    /// Clearing the field later has to re-close the interlock, not leave a configured-once sweep
    /// running unfiltered.
    func testClearingTheTitlesStopsSweepingAgain() throws {
        let settings = try makeSettings()
        try settings.set("Product Manager", forKey: SettingsKey.discoveryTitleInclude)
        XCTAssertTrue(DiscoverySettings.canSweep(settings))

        try settings.set("  ,  ", forKey: SettingsKey.discoveryTitleInclude)
        XCTAssertFalse(
            DiscoverySettings.canSweep(settings),
            "whitespace and stray commas are not keywords"
        )
    }
}
