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

    /// Whether sweeping is allowed to happen at all.
    ///
    /// **The interlock that lets these features ship on by default.** An empty `titleIncludeAny`
    /// matches every posting, so a sweep with no title keywords would push the daily cap's worth of
    /// arbitrary jobs — and the cap's worth of LLM spend — at a user who never asked for any of it.
    /// Onboarding asks for titles, so the ordinary path arrives configured; this is what holds if
    /// someone skips that step or clears the field later.
    ///
    /// Checked here rather than at each call site so no future caller can forget it.
    public static func canSweep(_ settings: SettingsStore) -> Bool {
        !list(settings.string(forKey: SettingsKey.discoveryTitleInclude)).isEmpty
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
    /// Title keywords have no existing equivalent and are left empty here — onboarding asks for
    /// them instead, because an empty include list matches everything and `canSweep` therefore holds
    /// the whole feature closed until at least one is set.
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
        return max(0, cap - spentToday(settings, now: now).spent)
    }

    /// Take `count` from today's allowance and return how much was actually granted.
    ///
    /// **Reserve before spending, not after.** Both runtime loops read the remaining budget, then
    /// `await` network work before recording what they used. Even on the main actor those awaits
    /// are suspension points, so two loops could each read "1 remaining", each create a job, and
    /// each then record one — two jobs against a cap of one. Reserving up front, synchronously,
    /// removes the window.
    ///
    /// Day and count are written as **one value** for the same reason a two-step write is unsafe:
    /// a crash between them could stamp today's date on yesterday's spend and suppress a whole day
    /// of scanning.
    @discardableResult
    public static func reserve(
        _ count: Int, settings: SettingsStore, now: Date = Date()
    ) -> Int {
        guard count > 0 else { return 0 }
        let cap = max(0, settings.int(forKey: SettingsKey.discoveryMaxIngestsPerDay))
        let (day, spent) = spentToday(settings, now: now)
        let granted = max(0, min(count, cap - spent))
        guard granted > 0 else { return 0 }
        writeSpend(day: day, spent: spent + granted, settings: settings)
        return granted
    }

    /// Reserve, run, and hand back whatever wasn't used — as one thing, because doing it in three
    /// was how Run Now came to reserve the whole per-sweep allowance and never release it. An empty
    /// or failed run could burn the day's budget and leave automatic search with nothing to spend.
    ///
    /// Also enforces the title interlock, so a caller cannot sweep with criteria that match every
    /// posting. `canSweep` was checked in both background loops and not in Run Now; a safety rule
    /// duplicated across call sites is a safety rule that drifts.
    ///
    /// Returns nil when the interlock is closed or the day's allowance is spent — in both cases
    /// nothing ran and nothing was reserved.
    @MainActor
    public static func withBudget<T>(
        _ settings: SettingsStore,
        now: Date = Date(),
        run: (Int) async -> (result: T, ingested: Int)?
    ) async -> T? {
        guard canSweep(settings) else { return nil }
        let granted = reserve(caps(from: settings).perSweep, settings: settings, now: now)
        guard granted > 0 else { return nil }
        // The day the reservation was stamped on. A sweep runs for minutes and the watched-company
        // loop runs around the clock, so the release below can land on the far side of midnight —
        // and refunding into a day this reservation was never counted against is what would
        // hand back allowance the new day hasn't spent.
        let reservedOn = dayFormatter.string(from: now)
        guard let outcome = await run(granted) else {
            release(granted, reservedOn: reservedOn, settings: settings)
            return nil
        }
        release(granted - outcome.ingested, reservedOn: reservedOn, settings: settings)
        return outcome.result
    }

    /// Hand back what a reservation didn't use, so an over-reservation doesn't burn the day.
    ///
    /// - Parameter reservedOn: the `yyyy-MM-dd` the reservation was made on, when the caller knows
    ///   it. A refund is void once the counter has rolled to a new day: the reservation was never
    ///   part of the new day's spend, so subtracting it would give away allowance — and, worse,
    ///   re-stamp the record with yesterday's date, which reads to the next `reserve` as a fresh
    ///   day and lifts the cap entirely.
    public static func release(
        _ count: Int, reservedOn: String? = nil, settings: SettingsStore, now: Date = Date()
    ) {
        guard count > 0 else { return }
        let (day, spent) = spentToday(settings, now: now)
        if let reservedOn, reservedOn != day {
            return
        }
        writeSpend(day: day, spent: max(0, spent - count), settings: settings)
    }

    /// The `yyyy-MM-dd` a reservation belongs to, for pairing a later `release` with it.
    static func dayString(_ date: Date) -> String {
        dayFormatter.string(from: date)
    }

    static func spentToday(_ settings: SettingsStore, now: Date) -> (day: String, spent: Int) {
        let today = dayFormatter.string(from: now)
        let stored = settings.string(forKey: SettingsKey.discoveryIngestsTodayValue)
        // "yyyy-MM-dd:count" — one value, so the date and the count cannot disagree.
        let parts = stored.split(separator: ":", maxSplits: 1).map(String.init)
        guard parts.count == 2, parts[0] == today, let spent = Int(parts[1]) else {
            return (today, 0)
        }
        return (today, spent)
    }

    static func writeSpend(day: String, spent: Int, settings: SettingsStore) {
        try? settings.set("\(day):\(spent)", forKey: SettingsKey.discoveryIngestsTodayValue)
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
    /// - Parameter alreadyCaptured: keys the store already holds, to skip hydration for postings the
    ///   user has. **No default on purpose.** It was optional-with-an-empty-default, and the Run Now
    ///   button promptly forgot it — which is how a safety parameter behaves. The invariant itself
    ///   now lives in the store (`AtomicIngestInput.createOnly`); this is only a cost saving, and
    ///   being made to pass it keeps that distinction visible.
    @discardableResult
    public func runOneDueSweep(
        criteria: DiscoveryCriteria,
        remainingDailyBudget: Int,
        alreadyCaptured: Set<String>,
        now: Date = Date()
    ) async -> SweepResult? {
        // `try?` flattens, so a store error and "nothing due" both land here as nil. That's the
        // behaviour we want: neither is a reason to sweep something.
        guard let searchSource = try? await nextDueSource(now: now) else { return nil }
        return await sweep(
            searchSource, criteria: criteria, remainingDailyBudget: remainingDailyBudget,
            alreadyCaptured: alreadyCaptured, now: now
        )
    }

    /// Sweep one *named* source, whatever else is due.
    ///
    /// Run Now used to mark its source due and then call `runOneDueSweep`, which picks the
    /// longest-waiting source — so with more than one source overdue the button swept a different
    /// company than the one clicked, and reported the result under the clicked one's name.
    @discardableResult
    public func runSweep(
        sourceID: String,
        criteria: DiscoveryCriteria,
        remainingDailyBudget: Int,
        alreadyCaptured: Set<String>,
        now: Date = Date()
    ) async -> SweepResult? {
        guard let searchSource = try? await store.searchSources().first(where: { $0.id == sourceID })
        else { return nil }
        return await sweep(
            searchSource, criteria: criteria, remainingDailyBudget: remainingDailyBudget,
            alreadyCaptured: alreadyCaptured, now: now
        )
    }

    private func sweep(
        _ searchSource: SearchSource,
        criteria: DiscoveryCriteria,
        remainingDailyBudget: Int,
        alreadyCaptured: Set<String>,
        now: Date
    ) async -> SweepResult? {
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
            alreadyCaptured: alreadyCaptured,
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
