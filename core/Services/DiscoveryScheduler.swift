import Foundation

/// Reads and writes gate-A criteria and the ingest caps (TASK-692, M3).
///
/// A thin bridge over `SettingsStore` rather than a stored object: the criteria are eight lists and
/// three numbers, and a settings row per field means the UI can bind to them the way every other
/// preference does.
public enum DiscoverySettings {
    /// Split a comma-separated setting the way `preferredLocations` already is, dropping blanks.
    ///
    /// The blank-dropping matters more than it looks: an empty keyword matches every string, so one
    /// stray trailing comma would silently turn a block list into a no-op.
    public static func list(_ raw: String) -> [String] {
        raw.split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    public static func criteria(from settings: SettingsStore) -> DiscoveryCriteria {
        DiscoveryCriteria(
            titleIncludeAny: list(settings.string(forKey: SettingsKey.discoveryTitleInclude)),
            titleExcludeAny: list(settings.string(forKey: SettingsKey.discoveryTitleExclude)),
            locationBlockHard: list(settings.string(forKey: SettingsKey.discoveryLocationBlockHard)),
            locationAlwaysAllow: list(settings.string(forKey: SettingsKey.discoveryLocationAlwaysAllow)),
            locationBlock: list(settings.string(forKey: SettingsKey.discoveryLocationBlock)),
            locationAllow: list(settings.string(forKey: SettingsKey.discoveryLocationAllow)),
            minSalaryIfPublished: settings.int(forKey: SettingsKey.discoveryMinSalary),
            maxAgeDays: settings.int(forKey: SettingsKey.discoveryMaxAgeDays)
        )
    }

    public static func caps(from settings: SettingsStore) -> DiscoveryCaps {
        DiscoveryCaps(
            perSweep: max(0, settings.int(forKey: SettingsKey.discoveryMaxIngestsPerSweep)),
            perDay: max(0, settings.int(forKey: SettingsKey.discoveryMaxIngestsPerDay))
        )
    }

    /// Copy the user's existing requirement settings into the discovery criteria, once.
    ///
    /// The user should recognise their own configuration rather than face a blank form. But this
    /// **seeds**, it doesn't alias: after this runs the two sets of keys are independent, so
    /// widening the search never re-badges existing jobs. The `seeded` flag means a user who
    /// deliberately empties a list doesn't get it refilled on the next launch.
    ///
    /// Title keywords have no existing equivalent and are left empty — and since an empty include
    /// list matches everything, that is precisely why automatic search ships off by default.
    @discardableResult
    public static func seedIfNeeded(_ settings: SettingsStore) -> Bool {
        guard !settings.bool(forKey: SettingsKey.discoveryCriteriaSeeded) else { return false }

        let preferred = settings.string(forKey: SettingsKey.preferredLocations)
        let remoteRegions = settings.string(forKey: SettingsKey.remoteEligibilityRegions)
        // `try?` is safe here and only here because every discovery key is non-keychain, and
        // `set(_:forKey:)` throws only for the six keychain-backed API-key keys.
        if !preferred.isEmpty {
            try? settings.set(preferred, forKey: SettingsKey.discoveryLocationAllow)
        }
        if !remoteRegions.isEmpty {
            try? settings.set(remoteRegions, forKey: SettingsKey.discoveryLocationAlwaysAllow)
        }
        let minSalary = settings.int(forKey: SettingsKey.minSalary)
        if minSalary > 0 {
            settings.setInt(minSalary, forKey: SettingsKey.discoveryMinSalary)
        }
        settings.setBool(true, forKey: SettingsKey.discoveryCriteriaSeeded)
        return true
    }

    // MARK: - Daily budget

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    /// How many ingests are still allowed today, across every source.
    ///
    /// Held in settings rather than derived from the ledger: "how many did discovery ingest today"
    /// is a different question from "how many rows exist", because a job the user deleted must not
    /// hand the sweeper back its budget.
    ///
    /// The day boundary is local, and a stale date resets the counter rather than carrying it — so
    /// a machine asleep for a week starts fresh rather than believing it has already spent today.
    public static func remainingDailyBudget(_ settings: SettingsStore, now: Date = Date()) -> Int {
        let cap = max(0, settings.int(forKey: SettingsKey.discoveryMaxIngestsPerDay))
        let today = dayFormatter.string(from: now)
        guard settings.string(forKey: SettingsKey.discoveryIngestsTodayDate) == today else {
            return cap
        }
        return max(0, cap - settings.int(forKey: SettingsKey.discoveryIngestsToday))
    }

    public static func recordIngests(
        _ count: Int, settings: SettingsStore, now: Date = Date()
    ) {
        guard count > 0 else { return }
        let today = dayFormatter.string(from: now)
        let spent = settings.string(forKey: SettingsKey.discoveryIngestsTodayDate) == today
            ? settings.int(forKey: SettingsKey.discoveryIngestsToday)
            : 0
        try? settings.set(today, forKey: SettingsKey.discoveryIngestsTodayDate)
        settings.setInt(spent + count, forKey: SettingsKey.discoveryIngestsToday)
    }
}

/// Picks the next source to sweep and records what happened (TASK-692, M3).
///
/// One source at a time, deliberately. Sweeping several concurrently would finish sooner and buy
/// nothing — the whole run is a handful of requests against boards that have no reason to receive a
/// burst — while making rate limiting and cancellation harder to reason about. It's the same pacing
/// discipline `AvailabilityBacklog` follows.
public struct DiscoveryScheduler: Sendable {
    let store: BackgroundStore
    let sweeper: DiscoverySweeper

    public init(store: BackgroundStore, sweeper: DiscoverySweeper) {
        self.store = store
        self.sweeper = sweeper
    }

    /// The source that has been waiting longest, or nil when nothing is due.
    ///
    /// Oldest-first so a source with a short interval can't starve the others: without the sort,
    /// whichever source happened to be inserted first would be swept every cycle.
    public func nextDueSource(now: Date = Date()) async throws -> SearchSource? {
        try await store.dueSearchSources(now: now).first
    }

    /// Sweep one due source, if there is one. Returns what it did, or nil if nothing was due.
    ///
    /// Deliberately does one unit of work per call rather than looping internally: the caller owns
    /// the pacing and the cancellation, and a scheduler that drains everything in one go would keep
    /// the app busy for as long as the user's slowest board takes to answer.
    @discardableResult
    public func runOneDueSweep(
        criteria: DiscoveryCriteria,
        remainingDailyBudget: Int,
        now: Date = Date()
    ) async -> SweepResult? {
        // `try?` flattens, so a store error and "nothing due" both land here as nil. That's the
        // behaviour we want: neither is a reason to sweep something.
        guard let searchSource = try? await nextDueSource(now: now) else { return nil }
        guard let source = searchSource.source else {
            // The stored `kind` names a vendor this build doesn't have — a downgrade, or a source
            // added by a newer version. Record it and move the clock on rather than retrying every
            // cycle forever.
            try? await store.recordSearchSourceRun(
                id: searchSource.id, status: .misconfigured,
                error: "no source of kind “\(searchSource.kind)”", now: now
            )
            return SweepResult(status: .misconfigured, error: "unknown source kind")
        }

        let result = await sweeper.sweep(
            source: source,
            config: searchSource.config,
            criteria: criteria,
            remainingDailyBudget: remainingDailyBudget,
            now: now
        )
        try? await store.recordSearchSourceRun(
            id: searchSource.id,
            status: result.status,
            found: result.found,
            passed: result.passed,
            ingested: result.ingested,
            error: result.error,
            now: now
        )
        return result
    }
}
