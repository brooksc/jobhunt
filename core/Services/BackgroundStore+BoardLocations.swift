import Foundation
import SwiftData

/// Restore job-board location strings lost when the discovery ledger dropped `rawJSON` (TASK-693).
///
/// The ledger keeps `rawJSON` for only the most recent sweep of a source and nils it on the next, so
/// the boards' own location text for jobs already ingested is gone from the store. A snapshot was
/// taken before it vanished; this reads that snapshot back in.
///
/// **Deliberately narrow — it fills `location` and nothing else.**
/// - It never sets or infers `remoteType`. Deriving a work arrangement from a location string is the
///   bug class that erased 223 arrangements (TASK-708) and invented salary bands; a `locationRaw` of
///   "Remote" is still the board's location text, not our verdict on the arrangement.
/// - It never overwrites a location that already says something. That is what makes it idempotent
///   and safe to re-run, and it means a hand-edited location outranks the board.
/// - It does not re-judge `meetsCriteria`. Filling a location can change that verdict, so run
///   `--recompute-criteria` afterwards; keeping the two passes separate keeps this one auditable.
public extension BackgroundStore {
    /// One row of the snapshot at `board-locations-<date>.json`.
    ///
    /// Every field is decoded with `decodeIfPresent`: this is a persisted JSON schema, and the
    /// project rule is that a declaration default is not a decoding default. A row missing a key
    /// must degrade to "can't use this one", never abort the whole file.
    struct BoardLocationRecord: Codable, Sendable {
        public var dedupKey: String?
        public var sourceID: String?
        public var url: String?
        public var title: String?
        public var locationRaw: String?

        public init(
            dedupKey: String? = nil,
            sourceID: String? = nil,
            url: String? = nil,
            title: String? = nil,
            locationRaw: String? = nil
        ) {
            self.dedupKey = dedupKey
            self.sourceID = sourceID
            self.url = url
            self.title = title
            self.locationRaw = locationRaw
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            dedupKey = try container.decodeIfPresent(String.self, forKey: .dedupKey)
            sourceID = try container.decodeIfPresent(String.self, forKey: .sourceID)
            url = try container.decodeIfPresent(String.self, forKey: .url)
            title = try container.decodeIfPresent(String.self, forKey: .title)
            locationRaw = try container.decodeIfPresent(String.self, forKey: .locationRaw)
        }

        public static func decode(_ data: Data) throws -> [BoardLocationRecord] {
            try JSONDecoder().decode([BoardLocationRecord].self, from: data)
        }
    }

    struct BoardLocationBackfillSummary: Sendable, Equatable {
        /// Rows in the snapshot file.
        public var recordsRead = 0
        /// Rows resolved to a job via `DiscoveredPosting.dedupKey`.
        public var matchedByDedupKey = 0
        /// Rows the dedup key missed but a normalised URL found.
        public var matchedByURL = 0
        /// Jobs whose empty `location` this run filled in.
        public var filled = 0
        /// Matched rows left alone because the job already states a location.
        public var skippedAlreadyPopulated = 0
        /// Rows whose `locationRaw` is empty — nothing to copy across.
        public var skippedBlankSource = 0
        /// Rows with no job in this store.
        public var unmatched = 0
        /// Captures given a `boardLocation`, so the fill survives a later re-extraction.
        public var boardLocationsRecorded = 0

        public init() {}
    }

    /// Fill empty `Job.location` values from a board-location snapshot. Returns what it did.
    func backfillBoardLocations(from records: [BoardLocationRecord]) throws -> BoardLocationBackfillSummary {
        var summary = BoardLocationBackfillSummary()
        summary.recordsRead = records.count
        let index = try jobLocationIndex()

        for record in records {
            let location = (record.locationRaw ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !location.isEmpty else {
                summary.skippedBlankSource += 1
                continue
            }
            // dedupKey first, URL second, and the two are counted apart so it stays visible which
            // path did the work — a run that matched everything by URL means the keys drifted.
            var job = record.dedupKey.flatMap { index.byDedupKey[$0] }
            if job != nil {
                summary.matchedByDedupKey += 1
            } else {
                job = record.url.flatMap { URLNormalizer.normalized($0) }.flatMap { index.byURL[$0] }
                if job != nil { summary.matchedByURL += 1 }
            }
            guard let job else {
                summary.unmatched += 1
                continue
            }
            guard (job.location ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                summary.skippedAlreadyPopulated += 1
                continue
            }
            job.location = location
            job.updatedAt = Date()
            summary.filled += 1

            // Make the fill durable. Without this the restore lasts only until the job is
            // re-extracted: the model reads a posting body that never states a location, writes
            // nothing, and the value is lost again — leaving the JSON snapshot as a file someone
            // has to keep forever. `Capture.boardLocation` is the field TASK-693 added for exactly
            // this, and it feeds the extraction prompt as the board's authoritative answer.
            //
            // Only filled when empty, and only for jobs whose location this pass actually restored.
            // The 432 matched jobs that already state a location are deliberately left alone: their
            // location came from somewhere else, and rewriting their prompt input is a broader
            // change than restoring lost data.
            if let capture = job.capture,
               (capture.boardLocation ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                capture.boardLocation = location
                summary.boardLocationsRecorded += 1
            }
        }

        if summary.filled > 0 {
            try modelContext.save()
        }
        return summary
    }

    /// Both lookup tables, built once. A few hundred jobs, so a single pass beats a fetch per record.
    private func jobLocationIndex() throws -> (byDedupKey: [String: Job], byURL: [String: Job]) {
        var byDedupKey: [String: Job] = [:]
        var byURL: [String: Job] = [:]
        for job in try modelContext.fetch(FetchDescriptor<Job>()) {
            guard let capture = job.capture else { continue }
            for urlString in [capture.url, capture.canonicalURL].compactMap(\.self) where !urlString.isEmpty {
                if let key = DiscoveredPosting.dedupKey(for: urlString) {
                    byDedupKey[key] = byDedupKey[key] ?? job
                }
                if let normalized = URLNormalizer.normalized(urlString) {
                    byURL[normalized] = byURL[normalized] ?? job
                }
            }
        }
        return (byDedupKey, byURL)
    }
}
