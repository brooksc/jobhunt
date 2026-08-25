import Foundation
import SwiftData

/// Ledger reads and writes (TASK-691, M2).
///
/// Kept out of `BackgroundStore.swift` because that file is already long, but deliberately *on*
/// `BackgroundStore` rather than in a second `@ModelActor`: the SQLite store is single-writer, so a
/// sweep must share the one context rather than opening its own.
public extension BackgroundStore {
    /// Which of these postings still need judging, in the order given.
    ///
    /// The filter that makes a sweep cheap. A board of 6,000 rows that hasn't changed since the last
    /// run returns nothing here, so no hydration request is made and no ingest is attempted.
    func unjudgedPostings(
        _ postings: [DiscoveredPosting], criteriaFingerprint: String
    ) throws -> [DiscoveredPosting] {
        guard !postings.isEmpty else { return [] }
        // One small keyed fetch per candidate rather than a full-table scan. Only postings that
        // already cleared the gate reach here — typically none or a handful per board — while the
        // ledger grows into the tens of thousands, so a scan per board would be the most expensive
        // thing in a market sweep by a wide margin.
        return try postings.filter { posting in
            let key = posting.dedupKey
            var descriptor = FetchDescriptor<DiscoveryLedgerEntry>(
                predicate: #Predicate { $0.dedupKey == key }
            )
            descriptor.fetchLimit = 1
            guard let entry = try modelContext.fetch(descriptor).first else { return true }
            return entry.needsReevaluation(under: criteriaFingerprint)
        }
    }

    /// Dedup keys for every posting already captured, however it got here.
    ///
    /// **The guard on "discovery only ever creates."** `ingestCapture`'s same-URL path is a
    /// *recapture*: it overwrites the stored capture, resets extraction and re-queues it. That is
    /// right for the browser extension, where a re-capture is the user deliberately refreshing a
    /// posting, and wrong for a sweep — a first market pass would otherwise re-extract every job the
    /// user already has whose posting is still open, spending real money to replace a description
    /// they were happy with.
    ///
    /// Keyed on `DuplicateDetector.atsPostingID` rather than the raw URL, because the two arrive by
    /// different routes: the extension captures `…/jobs/123?gh_src=abc` while a sweep sees
    /// `…/jobs/123`, and an exact string compare would call those two different jobs.
    ///
    /// Read once per slice, not per board — it is a scan of the capture table, and a few hundred
    /// rows once is nothing while the same scan 28,746 times is a sweep that never finishes.
    func capturedDedupKeys() throws -> Set<String> {
        var keys: Set<String> = []
        for capture in try modelContext.fetch(FetchDescriptor<Capture>()) {
            if let key = DiscoveredPosting.dedupKey(for: capture.url) {
                keys.insert(key)
            }
            if let canonical = capture.canonicalURL, !canonical.isEmpty,
               let key = DiscoveredPosting.dedupKey(for: canonical) {
                keys.insert(key)
            }
        }
        return keys
    }

    /// Record what a sweep decided, and refresh `lastSeenAt` on everything it saw again.
    ///
    /// `lastSeenAt` moving on an unchanged posting is what makes "this board hasn't listed that
    /// role since March" answerable later; without it the ledger can say a posting was seen once
    /// but not that it is still up.
    func recordDiscoveryOutcomes(
        _ outcomes: [(posting: DiscoveredPosting, outcome: DiscoveryOutcome, reason: DiscoveryRejectReason?)],
        criteriaFingerprint: String,
        now: Date = Date()
    ) throws {
        guard !outcomes.isEmpty else { return }
        let keys = Set(outcomes.map(\.posting.dedupKey))
        var byKey = Dictionary(
            try existingLedgerEntries(keys: keys).map { ($0.dedupKey, $0) },
            uniquingKeysWith: { first, _ in first }
        )

        for (posting, outcome, reason) in outcomes {
            if let entry = byKey[posting.dedupKey] {
                entry.outcomeRaw = outcome.rawValue
                entry.rejectReasonRaw = reason?.rawValue
                entry.criteriaFingerprint = criteriaFingerprint
                entry.lastSeenAt = now
                entry.rawJSON = Self.encodeRaw(posting)
            } else {
                let entry = DiscoveryLedgerEntry(
                    dedupKey: posting.dedupKey,
                    sourceID: posting.sourceID,
                    outcome: outcome,
                    rejectReason: reason,
                    criteriaFingerprint: criteriaFingerprint,
                    firstSeenAt: now,
                    lastSeenAt: now,
                    rawJSON: Self.encodeRaw(posting)
                )
                modelContext.insert(entry)
                // A second row for the same key in one batch would violate the unique constraint,
                // and a board that lists the same posting under two URLs does exist.
                byKey[posting.dedupKey] = entry
            }
        }
        try modelContext.save()
    }

    /// The ledger rows for a set of keys, fetched by key rather than by scanning.
    ///
    /// `unjudgedPostings` already refuses to scan the ledger per board, and the write path below it
    /// used to do exactly that — fetching every row and filtering in memory. On a watched Workday
    /// tenant the ledger holds a row per posting, so recording one board's handful of outcomes
    /// materialised tens of thousands of model objects.
    ///
    /// Chunked because this becomes a SQL `IN (…)`, and SQLite binds one variable per element: a
    /// 3,000-posting tenant would otherwise build a single statement past the host parameter limit.
    private func existingLedgerEntries(keys: Set<String>) throws -> [DiscoveryLedgerEntry] {
        let all = Array(keys)
        var found: [DiscoveryLedgerEntry] = []
        for start in stride(from: 0, to: all.count, by: 500) {
            let chunk = Array(all[start ..< min(start + 500, all.count)])
            found.append(contentsOf: try modelContext.fetch(
                FetchDescriptor<DiscoveryLedgerEntry>(
                    predicate: #Predicate { chunk.contains($0.dedupKey) }
                )
            ))
        }
        return found
    }

    /// Drop the retained raw rows for a source's previous sweep.
    ///
    /// Called at the start of each sweep so exactly one sweep's payloads are held per source: enough
    /// for the settings preview to replay gate A over real data, and not a copy of every board the
    /// user has ever pointed at. The keys stay — forgetting one means re-ingesting a job the user
    /// may have already archived.
    @discardableResult
    func clearRetainedRawRows(sourceID: String) throws -> Int {
        let entries = try modelContext.fetch(
            FetchDescriptor<DiscoveryLedgerEntry>(
                predicate: #Predicate { $0.sourceID == sourceID && $0.rawJSON != nil }
            )
        )
        for entry in entries {
            entry.rawJSON = nil
        }
        if !entries.isEmpty {
            try modelContext.save()
        }
        return entries.count
    }

    /// The retained raw rows, for the settings preview.
    ///
    /// Only rows that actually carry a payload: raw JSON is kept for one sweep per source, so the
    /// overwhelming majority of the ledger has `rawJSON == nil` and fetching it to discard it is
    /// the settings pane's most expensive query.
    func retainedRawPostings(sourceID: String? = nil) throws -> [DiscoveredPosting] {
        let descriptor: FetchDescriptor<DiscoveryLedgerEntry> = if let sourceID {
            FetchDescriptor(
                predicate: #Predicate { $0.rawJSON != nil && $0.sourceID == sourceID }
            )
        } else {
            FetchDescriptor(predicate: #Predicate { $0.rawJSON != nil })
        }
        return try modelContext.fetch(descriptor)
            .compactMap(\.rawJSON)
            .compactMap { BackgroundStore.decodeRaw($0) }
    }

    /// How many postings this source has ever had each outcome — the rejection histogram.
    func discoveryOutcomeCounts(sourceID: String? = nil) throws -> [String: Int] {
        var counts: [String: Int] = [:]
        let descriptor: FetchDescriptor<DiscoveryLedgerEntry> = if let sourceID {
            FetchDescriptor(predicate: #Predicate { $0.sourceID == sourceID })
        } else {
            FetchDescriptor()
        }
        for entry in try modelContext.fetch(descriptor) {
            let key = entry.outcome == .rejected
                ? "rejected.\(entry.rejectReasonRaw ?? "unknown")"
                : entry.outcomeRaw
            counts[key, default: 0] += 1
        }
        return counts
    }

    // MARK: - Raw row encoding

    /// The raw row is stored as JSON rather than as columns because nothing queries it — the
    /// preview replays gate A over the whole set in memory, and a schema of its own would have to
    /// be migrated every time a vendor starts publishing a new field.
    static func encodeRaw(_ posting: DiscoveredPosting) -> String? {
        guard let data = try? JSONEncoder().encode(RawRow(posting)) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func decodeRaw(_ json: String) -> DiscoveredPosting? {
        guard let data = json.data(using: .utf8),
              let row = try? JSONDecoder().decode(RawRow.self, from: data) else { return nil }
        return row.posting
    }

    /// `DiscoveredPosting` isn't `Codable` itself — it's the sweep's in-memory shape, and making it
    /// `Codable` would freeze its field names into a persisted format.
    struct RawRow: Codable {
        var dedupKey: String
        var url: String
        var title: String
        var company: String?
        var locationRaw: String?
        var firstPublished: Date?
        var salaryMinPublished: Int?
        var salaryMaxPublished: Int?
        var salaryCurrency: String?
        var descriptionPlain: String?
        var sourceID: String

        init(_ posting: DiscoveredPosting) {
            dedupKey = posting.dedupKey
            url = posting.url
            title = posting.title
            company = posting.company
            locationRaw = posting.locationRaw
            firstPublished = posting.firstPublished
            salaryMinPublished = posting.salaryMinPublished
            salaryMaxPublished = posting.salaryMaxPublished
            salaryCurrency = posting.salaryCurrency
            descriptionPlain = posting.descriptionPlain
            sourceID = posting.sourceID
        }

        var posting: DiscoveredPosting {
            DiscoveredPosting(
                dedupKey: dedupKey, url: url, title: title, company: company,
                locationRaw: locationRaw, firstPublished: firstPublished,
                salaryMinPublished: salaryMinPublished, salaryMaxPublished: salaryMaxPublished,
                salaryCurrency: salaryCurrency, descriptionPlain: descriptionPlain,
                sourceID: sourceID
            )
        }
    }
}

// MARK: - Search sources

public extension BackgroundStore {
    /// Sources due for a sweep, longest-waiting first.
    ///
    /// The sort is what stops one source starving the others: without it, whichever row happened to
    /// be inserted first would be swept every cycle while a source with the same interval never came
    /// up. `nil` sorts first, which is right — a source that has never run has waited longest.
    func dueSearchSources(now: Date = Date()) throws -> [SearchSource] {
        try modelContext.fetch(
            FetchDescriptor<SearchSource>(
                sortBy: [SortDescriptor(\.nextRunAt, order: .forward)]
            )
        )
        .filter { $0.isDue(now: now) }
    }

    func searchSources() throws -> [SearchSource] {
        try modelContext.fetch(
            FetchDescriptor<SearchSource>(sortBy: [SortDescriptor(\.label, order: .forward)])
        )
    }

    /// Persist the outcome of a run. Also what moves `nextRunAt`, so a source that fails still waits
    /// its interval rather than being retried on every cycle.
    func recordSearchSourceRun(
        id: String,
        status: SearchSourceStatus,
        found: Int = 0,
        passed: Int = 0,
        ingested: Int = 0,
        error: String? = nil,
        now: Date = Date()
    ) throws {
        let sources = try modelContext.fetch(FetchDescriptor<SearchSource>())
        guard let source = sources.first(where: { $0.id == id }) else { return }
        source.recordRun(
            status: status, found: found, passed: passed, ingested: ingested, error: error, now: now
        )
        try modelContext.save()
    }

    @discardableResult
    func addSearchSource(
        kind: String, label: String, config: SourceConfig, intervalHours: Int = 12
    ) throws -> String {
        let source = SearchSource(
            kind: kind, label: label, config: config, intervalHours: intervalHours
        )
        modelContext.insert(source)
        try modelContext.save()
        return source.id
    }

    func deleteSearchSource(id: String) throws {
        let sources = try modelContext.fetch(FetchDescriptor<SearchSource>())
        guard let source = sources.first(where: { $0.id == id }) else { return }
        modelContext.delete(source)
        try modelContext.save()
    }

    func setSearchSourceEnabled(id: String, enabled: Bool) throws {
        let sources = try modelContext.fetch(FetchDescriptor<SearchSource>())
        guard let source = sources.first(where: { $0.id == id }) else { return }
        source.enabled = enabled
        source.updatedAt = Date()
        try modelContext.save()
    }

    /// Make a source due immediately — the "Run now" button.
    func markSearchSourceDue(id: String, now: Date = Date()) throws {
        let sources = try modelContext.fetch(FetchDescriptor<SearchSource>())
        guard let source = sources.first(where: { $0.id == id }) else { return }
        source.nextRunAt = now
        try modelContext.save()
    }
}

public extension BackgroundStore {
    /// Repoint a source at a different board, after re-resolution found one.
    ///
    /// Also clears the health counters: the old `consecutiveEmptyRuns` describes a board this source
    /// no longer points at, and leaving it would keep the "may have moved" warning on a source that
    /// was just repaired.
    func updateSearchSourceConfig(
        id: String, kind: String, config: SourceConfig, now: Date = Date()
    ) throws {
        let sources = try modelContext.fetch(FetchDescriptor<SearchSource>())
        guard let source = sources.first(where: { $0.id == id }) else { return }
        source.kind = kind
        source.config = config
        source.consecutiveEmptyRuns = 0
        source.lastError = nil
        source.lastStatusRaw = SearchSourceStatus.never.rawValue
        // Due immediately, so the user sees whether the repair worked rather than waiting a cycle.
        source.nextRunAt = now
        source.updatedAt = now
        try modelContext.save()
    }
}
