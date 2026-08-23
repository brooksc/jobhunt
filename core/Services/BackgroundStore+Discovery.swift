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
        let keys = Set(postings.map(\.dedupKey))
        // Fetch the whole set at once rather than per key: one round trip beats 6,000, and the
        // predicate can't reach into a Swift Set, so the membership test is done in memory.
        let existing = try modelContext.fetch(FetchDescriptor<DiscoveryLedgerEntry>())
            .filter { keys.contains($0.dedupKey) }
        let judged = Dictionary(existing.map { ($0.dedupKey, $0) }, uniquingKeysWith: { first, _ in first })

        return postings.filter { posting in
            guard let entry = judged[posting.dedupKey] else { return true }
            return entry.needsReevaluation(under: criteriaFingerprint)
        }
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
        let existing = try modelContext.fetch(FetchDescriptor<DiscoveryLedgerEntry>())
            .filter { keys.contains($0.dedupKey) }
        var byKey = Dictionary(existing.map { ($0.dedupKey, $0) }, uniquingKeysWith: { first, _ in first })

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

    /// Drop the retained raw rows for a source's previous sweep.
    ///
    /// Called at the start of each sweep so exactly one sweep's payloads are held per source: enough
    /// for the settings preview to replay gate A over real data, and not a copy of every board the
    /// user has ever pointed at. The keys stay — forgetting one means re-ingesting a job the user
    /// may have already archived.
    @discardableResult
    func clearRetainedRawRows(sourceID: String) throws -> Int {
        let entries = try modelContext.fetch(FetchDescriptor<DiscoveryLedgerEntry>())
            .filter { $0.sourceID == sourceID && $0.rawJSON != nil }
        for entry in entries {
            entry.rawJSON = nil
        }
        if !entries.isEmpty {
            try modelContext.save()
        }
        return entries.count
    }

    /// The retained raw rows, for the settings preview.
    func retainedRawPostings(sourceID: String? = nil) throws -> [DiscoveredPosting] {
        try modelContext.fetch(FetchDescriptor<DiscoveryLedgerEntry>())
            .filter { sourceID == nil || $0.sourceID == sourceID }
            .compactMap(\.rawJSON)
            .compactMap { BackgroundStore.decodeRaw($0) }
    }

    /// How many postings this source has ever had each outcome — the rejection histogram.
    func discoveryOutcomeCounts(sourceID: String? = nil) throws -> [String: Int] {
        var counts: [String: Int] = [:]
        for entry in try modelContext.fetch(FetchDescriptor<DiscoveryLedgerEntry>())
            where sourceID == nil || entry.sourceID == sourceID {
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
