// Large cohesive file; splitting deferred (TASK-545).
// swiftlint:disable file_length type_body_length function_body_length
import Foundation
import SwiftData

// MARK: - BackgroundStore errors

public enum BackgroundStoreError: Error, LocalizedError, Sendable {
    case notFound(String)
    case multipleMatches(count: Int)
    /// Two rows share an id the caller asked to change — the store is corrupt, and which row was
    /// meant is unknowable (TASK-678).
    case duplicateJobIDs([String])
    public var errorDescription: String? {
        switch self {
        case let .notFound(id): return "Record not found: \(id)"
        case let .multipleMatches(count): return "Expected exactly one match but found \(count)"
        case let .duplicateJobIDs(ids):
            return "The store holds more than one job with the same id (\(ids.joined(separator: ", "))). "
                + "Refusing to change an ambiguous row — back up the store and repair the duplicates."
        }
    }
}

// MARK: - Atomic ingest types

public struct AtomicIngestInput: Sendable {
    public let captureID: String
    public let jobID: String
    public let url: String
    public let canonicalURL: String?
    public let pageTitle: String
    public let selectedText: String?
    public let visibleText: String?
    public let cleanedDescription: String?
    public let structuredDataJSON: String?
    public let userNote: String?
    public let rawHash: String
    public let cleanedHash: String?
}

public struct AtomicIngestResult: Sendable {
    public let captureID: String
    public let jobNumber: Int
    public let isDuplicate: Bool
}

/// Sendable tally of LLM-queue request statuses (for diagnostics).
public struct LLMQueueCounts: Sendable {
    public let queued: Int
    public let running: Int
    public let failed: Int
    public init(queued: Int, running: Int, failed: Int) {
        self.queued = queued
        self.running = running
        self.failed = failed
    }
}

struct LLMCompletionMetadata {
    let requestID: String
    let jobID: String
    let attempt: Int
    let modelRequested: String?
    let baseURL: String?
    let startedAt: Date
    let finishedAt: Date
    let durationMs: Int
}

// MARK: - BackgroundStore

/// All background writes (extraction, availability, bulk ops, demo seeding) funnel through here.
/// UI @Query views update automatically via SwiftData change tracking — no manual broadcast needed.
@ModelActor
public actor BackgroundStore {
    /// Test-only fault injection (TASK-479). When set, `fetch` throws the given error before touching
    /// the context, so the degraded-state paths in QueueActor / AvailabilityChecker (which SwiftData
    /// can't otherwise be made to error on demand) get real coverage. Nil in production.
    private var fetchFault: Error?
    private var saveFault: Error?

    /// Make the next (and subsequent) `fetch` calls throw `error`, or clear with nil.
    public func setFetchFault(_ error: Error?) {
        fetchFault = error
    }

    /// Test-only fault injection for atomic transition rollback coverage.
    public func setSaveFault(_ error: Error?) {
        saveFault = error
    }

    private func saveAtomically() throws {
        do {
            if let saveFault { throw saveFault }
            try modelContext.save()
        } catch {
            modelContext.rollback()
            throw error
        }
    }

    /// Insert a single model and save immediately.
    public func insert(_ model: some PersistentModel) throws {
        modelContext.insert(model)
        try modelContext.save()
    }

    /// Insert a batch of models and save once at the end.
    public func insertBatch(_ models: [some PersistentModel]) throws {
        for model in models {
            modelContext.insert(model)
        }
        try modelContext.save()
    }

    /// Apply a mutation closure over fetched models, then save.
    public func update<T: PersistentModel>(
        _: T.Type,
        predicate: Predicate<T>? = nil,
        mutation: (T) -> Void
    ) throws {
        var descriptor = FetchDescriptor<T>()
        if let predicate {
            descriptor.predicate = predicate
        }
        let items = try modelContext.fetch(descriptor)
        items.forEach(mutation)
        try modelContext.save()
    }

    /// Persist status changes and their timeline events as one invariant-sized transaction.
    public func setJobStatus(_ status: JobStatus, jobIDs: [String]) throws {
        let uniqueIDs = Array(Set(jobIDs))
        guard !uniqueIDs.isEmpty else { return }

        let allJobs = try modelContext.fetch(FetchDescriptor<Job>())
        // Built by hand rather than with `Dictionary(uniqueKeysWithValues:)`, which TRAPS on a
        // duplicate key — taking the process down on an ordinary status change, with no diagnosis
        // (TASK-678). A repeated URL query parameter killed the app this way once already; this is
        // the same construct applied to runtime data.
        //
        // A duplicate elsewhere in the store doesn't block unrelated work — but a duplicate among the
        // jobs being CHANGED does, because which row was meant is unknowable and picking one silently
        // would corrupt the answer rather than report the corruption.
        var jobsByID: [String: Job] = [:]
        var duplicated: Set<String> = []
        for job in allJobs where jobsByID.updateValue(job, forKey: job.id) != nil {
            duplicated.insert(job.id)
        }
        let ambiguous = duplicated.intersection(uniqueIDs)
        if !ambiguous.isEmpty {
            throw BackgroundStoreError.duplicateJobIDs(ambiguous.sorted())
        }
        if !duplicated.isEmpty {
            // Not fatal here, but not silent either: the store needs repairing.
            NSLog("BackgroundStore: duplicate job ids present: \(duplicated.sorted())")
        }
        for id in uniqueIDs where jobsByID[id] == nil {
            throw BackgroundStoreError.notFound(id)
        }

        for id in uniqueIDs {
            guard let job = jobsByID[id] else { continue }
            let oldStatus = job.status
            job.status = status
            // TASK-504: stamp the first time the job becomes .applied; never overwrite on re-apply so
            // "Applied {date}" reflects the original application, not a later status bounce.
            if status == .applied, job.appliedAt == nil {
                job.appliedAt = Date()
            }
            if status != .duplicate, job.duplicateOfJobID != nil {
                job.duplicateOfJobID = nil
                job.duplicateConfidence = nil
            }
            job.updatedAt = Date()

            let event = JobEvent(
                eventType: "status",
                note: "Status changed from \(oldStatus.rawValue) to \(status.rawValue)"
            )
            event.job = job
            modelContext.insert(event)
        }
        try saveAtomically()
    }

    /// What an ATS lookup needs from a job, read in one hop.
    ///
    /// A value type crossing the actor boundary rather than the `Job` itself — `Job` is not
    /// `Sendable`, and a second fetch inside the apply would race with the network wait.
    public struct ATSIdentity: Sendable {
        public let atsID: String
        public let company: String?
        public let urlString: String
        public let provider: any ATSProvider
    }

    /// The posting's ATS id and the provider that can read it, or nil when it's on an ATS we can't
    /// query authoritatively (TASK-636). The capture URL is checked first because it keeps the
    /// `?gh_jid=` that an extracted application URL may not carry.
    public func atsIdentity(jobID: String) throws -> ATSIdentity? {
        guard let job = try modelContext.fetch(
            FetchDescriptor<Job>(predicate: #Predicate { $0.id == jobID })
        ).first else { return nil }
        let capture = job.capture
        let urls = [capture?.url, job.applicationURL, capture?.canonicalURL]
        guard let resolved = ATSRegistry.resolve(urls: urls) else { return nil }
        return ATSIdentity(
            atsID: resolved.atsID,
            company: job.company,
            urlString: capture?.url ?? job.applicationURL ?? "",
            provider: resolved.provider
        )
    }

    /// What a Greenhouse refresh changed, so the caller can report it rather than claiming success
    /// over a no-op.
    public struct GreenhouseRefreshOutcome: Sendable, Equatable {
        public var descriptionChanged = false
        public var titleChanged = false
        public var locationChanged = false
        /// Fields left alone because the user had edited them by hand.
        public var skippedOverrides: [String] = []
        /// The ATS publish/update dates were recorded. Tracked separately from the content changes
        /// because it alone doesn't warrant a re-extraction.
        public var timestampsChanged = false
        public var board = ""
        /// Which ATS answered, for the message the user reads.
        public var providerName = ""

        public var changedAnything: Bool {
            descriptionChanged || titleChanged || locationChanged
        }
    }

    /// Replaces a job's captured description with the canonical Greenhouse posting and backfills the
    /// clean metadata (TASK-632).
    ///
    /// Manual overrides are honoured exactly as extraction honours them: a field the user edited by
    /// hand is skipped and *reported*, since silently keeping the user's value is indistinguishable
    /// from the refresh not having worked.
    ///
    /// The description itself is not override-protected — it isn't user-authored, it's a scrape, and
    /// replacing a JavaScript-shell scrape with the employer's own text is the entire point.
    @discardableResult
    public func applyATSRefresh(
        jobID: String,
        posting: ATSPosting
    ) throws -> GreenhouseRefreshOutcome {
        guard let job = try modelContext.fetch(
            FetchDescriptor<Job>(predicate: #Predicate { $0.id == jobID })
        ).first else {
            throw BackgroundStoreError.notFound(jobID)
        }

        var outcome = GreenhouseRefreshOutcome()
        outcome.board = posting.boardKey
        outcome.providerName = posting.providerName
        let overrides = manualFieldOverrideSet(job.manualFieldOverridesJSON)

        let cleaned = posting.contentPlain
        if !cleaned.isEmpty, let capture = job.capture, capture.cleanedDescription != cleaned {
            // Keep `visibleText` in step: a later re-clean recomputes `cleanedDescription` from it,
            // and leaving the old shell text there would silently undo this refresh.
            capture.visibleText = posting.contentPlain
            capture.cleanedDescription = cleaned
            capture.cleanedHash = DuplicateDetector.cleanedHash(from: cleaned)
            job.cleanedTextBytes = cleaned.utf8.count
            outcome.descriptionChanged = true
        }

        if let title = posting.title, !title.isEmpty, title != job.title {
            if overrides.contains("title") {
                outcome.skippedOverrides.append("title")
            } else {
                job.title = title
                outcome.titleChanged = true
            }
        }

        if let location = posting.locationName?.trimmingCharacters(in: .whitespacesAndNewlines),
           !location.isEmpty, location != job.location {
            if overrides.contains("location") {
                outcome.skippedOverrides.append("location")
            } else {
                job.location = location
                outcome.locationChanged = true
            }
        }

        // Timestamps are recorded whether or not anything else changed: knowing the posting is
        // four months old is useful precisely when the text hasn't moved (TASK-633).
        if job.atsFirstPublishedAt != posting.firstPublished || job.atsUpdatedAt != posting.updatedAt {
            job.atsFirstPublishedAt = posting.firstPublished
            job.atsUpdatedAt = posting.updatedAt
            outcome.timestampsChanged = true
        }

        if outcome.changedAnything || outcome.timestampsChanged {
            job.updatedAt = Date()
            try saveAtomically()
        }
        return outcome
    }

    /// One-time re-clean: recompute every capture's `cleanedDescription` with the current cleaner
    /// (after improving JSON-LD preference / boilerplate stripping), refreshing the cleaned hash and
    /// the job's byte count. Returns the number of captures whose text changed.
    @discardableResult
    public func recleanAllCaptures() throws -> Int {
        var changed = 0
        try update(Capture.self) { capture in
            let structured: [[String: Any]]
            if let json = capture.structuredDataJSON,
               let data = json.data(using: .utf8),
               let parsed = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
                structured = parsed
            } else {
                structured = []
            }
            let cleaned = cleanDescription(
                selectedText: capture.selectedText ?? "",
                visibleText: capture.visibleText ?? "",
                structuredData: structured
            )
            let newValue = cleaned.isEmpty ? nil : cleaned
            guard capture.cleanedDescription != newValue else { return }
            capture.cleanedDescription = newValue
            capture.cleanedHash = newValue == nil ? nil : DuplicateDetector.cleanedHash(from: cleaned)
            capture.job?.cleanedTextBytes = newValue?.utf8.count ?? 0
            changed += 1
        }
        return changed
    }

    /// One-time backfill: older finished requests (fit requests in particular) never persisted
    /// `model`, so they render "—" in the queue. Recover it from each request's recorded attempt
    /// history (newest attempt's returned model, falling back to the requested model). Idempotent —
    /// only touches finished rows that still have no model. Run out-of-band via JobhuntMigrator.
    public func backfillRequestModels() throws {
        try update(
            LLMRequest.self,
            predicate: #Predicate { $0.model == nil && $0.finishedAt != nil }
        ) { req in
            let model = req.attempts
                .sorted { $0.attempt > $1.attempt }
                .lazy
                .compactMap { $0.modelReturned ?? $0.modelRequested }
                .first { !$0.isEmpty }
            if let model { req.model = model }
        }
    }

    /// One-time cleanup: delete orphaned fit scores (no resume linked) and recompute the denormalized
    /// job fit mirror for each affected job. These arise from legacy/unmigrated rows whose resume
    /// reference didn't survive migration; they otherwise render as a model name and hijack "Best
    /// match". Returns the number of orphan records deleted. Run out-of-band via JobhuntMigrator.
    @discardableResult
    public func pruneOrphanFitScores() throws -> Int {
        let orphans = try modelContext.fetch(
            FetchDescriptor<JobFitScore>(predicate: #Predicate { $0.resume == nil })
        )
        guard !orphans.isEmpty else { return 0 }
        // Collect affected jobs before deleting (the relationship is nilled on delete).
        var affected: [Job] = []
        for orphan in orphans where orphan.job != nil {
            if let job = orphan.job, !affected.contains(where: { $0.persistentModelID == job.persistentModelID }) {
                affected.append(job)
            }
        }
        let count = orphans.count
        for orphan in orphans {
            modelContext.delete(orphan)
        }
        for job in affected {
            recomputeJobFitSummary(job)
        }
        try modelContext.save()
        return count
    }

    /// Apply a mutation to exactly one model matching `predicate`.
    /// Throws `notFound` if no row matches, or `multipleMatches` if more than one row matches.
    public func updateOne<T: PersistentModel>(
        _: T.Type,
        predicate: Predicate<T>,
        id: String,
        mutation: (T) -> Void
    ) throws {
        var descriptor = FetchDescriptor<T>()
        descriptor.predicate = predicate
        let items = try modelContext.fetch(descriptor)
        guard !items.isEmpty else { throw BackgroundStoreError.notFound(id) }
        guard items.count == 1 else { throw BackgroundStoreError.multipleMatches(count: items.count) }
        mutation(items[0])
        try modelContext.save()
    }

    /// Delete exactly one model matching `predicate`.
    /// Throws `notFound` if no row matches, or `multipleMatches` if more than one row matches.
    public func deleteOne<T: PersistentModel>(
        _: T.Type,
        predicate: Predicate<T>,
        id: String
    ) throws {
        var descriptor = FetchDescriptor<T>()
        descriptor.predicate = predicate
        let items = try modelContext.fetch(descriptor)
        guard !items.isEmpty else { throw BackgroundStoreError.notFound(id) }
        guard items.count == 1 else { throw BackgroundStoreError.multipleMatches(count: items.count) }
        modelContext.delete(items[0])
        try modelContext.save()
    }

    /// Delete all models matching a predicate, then save.
    public func delete<T: PersistentModel>(
        _: T.Type,
        predicate: Predicate<T>
    ) throws {
        var descriptor = FetchDescriptor<T>()
        descriptor.predicate = predicate
        let items = try modelContext.fetch(descriptor)
        items.forEach { modelContext.delete($0) }
        try modelContext.save()
    }

    /// Delete all rows of the given type. Use only when full-table deletion is intentional.
    public func deleteAll<T: PersistentModel>(_: T.Type) throws {
        let items = try modelContext.fetch(FetchDescriptor<T>())
        items.forEach { modelContext.delete($0) }
        try modelContext.save()
    }

    /// Delete models matching `predicate` that also pass an in-memory `filter`, then save.
    /// Use when the predicate can narrow the fetch (e.g. by date) but the final filter
    /// requires enum comparison that SwiftData predicates cannot express.
    public func deleteFiltered<T: PersistentModel>(
        _: T.Type,
        predicate: Predicate<T>,
        where filter: (T) -> Bool
    ) throws {
        var descriptor = FetchDescriptor<T>()
        descriptor.predicate = predicate
        let items = try modelContext.fetch(descriptor)
        items.filter(filter).forEach { modelContext.delete($0) }
        try modelContext.save()
    }

    /// Fetch items in the background context.
    public func fetch<T: PersistentModel>(_ descriptor: FetchDescriptor<T>) throws -> sending [T] {
        if let fetchFault { throw fetchFault } // TASK-479 test seam (nil in production)
        return try modelContext.fetch(descriptor)
    }

    /// Save the current context state.
    public func save() throws {
        try modelContext.save()
    }

    /// Update job fit fields AND create/update the JobFitScore record for a (job, resume) pair.
    /// Job-level fitScore/fitStatus/fitScoreJSON reflect the active resume's score only —
    /// if the resume is not active, only the JobFitScore record is updated.
    public func saveFitScore(
        jobID: String,
        resumeID: String,
        overall: Int,
        fitJSON: String?,
        model: String?,
        scoredAt: Date
    ) throws {
        try applyFitScore(
            jobID: jobID,
            resumeID: resumeID,
            overall: overall,
            fitJSON: fitJSON,
            model: model,
            scoredAt: scoredAt
        )
        try modelContext.save()
    }

    private func applyFitScore(
        jobID: String,
        resumeID: String,
        overall: Int,
        fitJSON: String?,
        model: String?,
        scoredAt: Date
    ) throws {
        let jobs = try modelContext.fetch(FetchDescriptor<Job>(predicate: #Predicate { $0.id == jobID }))
        guard let job = jobs.first else { throw BackgroundStoreError.notFound(jobID) }

        let existing = job.fitScores.first { $0.resume?.id == resumeID }
        let record: JobFitScore
        let resume: Resume?
        if let existing {
            record = existing
            resume = existing.resume
        } else {
            record = JobFitScore()
            modelContext.insert(record)
            record.job = job
            let resumes = try modelContext.fetch(FetchDescriptor<Resume>(predicate: #Predicate { $0.id == resumeID }))
            resume = resumes.first
            record.resume = resume
        }
        record.fitScore = overall
        record.fitStatus = .succeeded
        record.fitScoreJSON = fitJSON
        record.model = model
        record.scoredAt = scoredAt
        record.updatedAt = Date()
        // Record WHICH résumé text produced this score, so a later edit can mark it stale instead of
        // deleting it.
        record.resumeTextHash = resume.map { ResumeFingerprint.hash($0.text) }

        // Job-level mirror reflects the BEST score across all resumes (Electron parity).
        recomputeJobFitSummary(job)
    }

    /// Recompute a job's denormalized fit mirror from the best-scoring resume across ALL its
    /// fit-score records (Electron parity: jobs.fit_score = MAX across resumes). Falls back to
    /// running/pending/failed/none when no resume has a numeric score yet.
    private func recomputeJobFitSummary(_ job: Job) {
        let computed = computedFitMirror(for: job)
        job.fitScore = computed.score
        job.fitStatus = computed.status
        job.fitScoreJSON = computed.json
        job.updatedAt = Date()
    }

    /// Pure computation of a job's denormalized fit mirror: the best score across the résumés the user
    /// is currently applying with. Falls back to running/pending/failed/none when none has a numeric
    /// score yet. No mutation/side effects.
    private func computedFitMirror(for job: Job) -> (score: Int?, status: FitStatus, json: String?) {
        // Only ACTIVE résumés count. A deactivated résumé is one the user has stopped applying with, so
        // its score no longer describes their fit — leaving it in meant a job's headline number could
        // come from a résumé they'd shelved months ago. Scores are kept, not deleted, so re-activating
        // restores them (nothing is destroyed by deactivating).
        //
        // An orphaned score (no resume) is a legacy/unmigrated artifact and never drives the number.
        let scored = job.fitScores.filter { $0.fitScore != nil && ($0.resume?.active ?? false) }
        if let best = scored.max(by: { ($0.fitScore ?? 0) < ($1.fitScore ?? 0) }) {
            return (best.fitScore, .succeeded, best.fitScoreJSON)
        } else if job.fitScores.contains(where: { $0.fitStatus == .running && ($0.resume?.active ?? false) }) {
            return (nil, .running, nil)
        } else if job.fitScores.contains(where: { $0.fitStatus == .pending && ($0.resume?.active ?? false) }) {
            return (nil, .pending, nil)
        } else if job.fitScores.contains(where: { $0.fitStatus == .failed && ($0.resume?.active ?? false) }) {
            return (nil, .failed, nil)
        } else {
            return (nil, FitStatus.none, nil)
        }
    }

    /// The job's headline fit score — the ACTIVE-résumé mirror, not any one résumé's result.
    ///
    /// The ready-notification used to advertise whatever score had just been computed, so manually
    /// rescoring a shelved résumé would announce a number the app itself no longer shows anywhere.
    public func jobMirrorScore(jobNumber: Int) throws -> Int? {
        try modelContext.fetch(
            FetchDescriptor<Job>(predicate: #Predicate { $0.jobNumber == jobNumber })
        ).first?.fitScore
    }

    /// One-time cleanup: recompute every job's denormalized fit mirror, touching only jobs whose
    /// mirror actually drifted from the best resume-linked score (so it doesn't bump updatedAt on
    /// every row). Drift accumulates from migration or scores deleted without a recompute. Returns
    /// the number of jobs corrected. Run out-of-band via JobhuntMigrator.
    @discardableResult
    public func recomputeAllJobFitMirrors() throws -> Int {
        var changed = 0
        for job in try modelContext.fetch(FetchDescriptor<Job>()) {
            let computed = computedFitMirror(for: job)
            guard job.fitScore != computed.score
                || job.fitStatus != computed.status
                || job.fitScoreJSON != computed.json else { continue }
            job.fitScore = computed.score
            job.fitStatus = computed.status
            job.fitScoreJSON = computed.json
            job.updatedAt = Date()
            changed += 1
        }
        if changed > 0 { try modelContext.save() }
        return changed
    }

    /// Collapse stored `seniority` onto the canonical bands.
    ///
    /// 55 distinct values across 415 jobs — case duplicates, five spellings of mid-level, and strings
    /// with no level in them at all ("5+ years", "III"). That text feeds the fit-scoring prompt's
    /// `experience_level` dimension, so the mess was degrading scores, not just blocking a filter.
    ///
    /// Idempotent: the normalizer maps every canonical value to itself, so a second run changes
    /// nothing. Values carrying no level become nil rather than a guessed band.
    public func normalizeStoredSeniority() throws -> (changed: Int, cleared: Int) {
        var changed = 0
        var cleared = 0
        for job in try modelContext.fetch(FetchDescriptor<Job>()) {
            guard let raw = job.seniority else { continue }
            let normalized = SeniorityNormalizer.normalize(raw)
            guard normalized != raw else { continue }
            job.seniority = normalized
            job.updatedAt = Date()
            changed += 1
            if normalized == nil { cleared += 1 }
        }
        if changed > 0 { try modelContext.save() }
        return (changed, cleared)
    }

    /// Re-run the evidence check over every stored fit analysis, marking verdicts whose quoted
    /// evidence no résumé supports.
    ///
    /// **Marks only — no score changes.** See `EvidenceCheck.apply`: an exact-substring test can't
    /// tell an invented claim from a paraphrase, and against hand labels the demote-on-invention rule
    /// was wrong 6 times in 7. Because nothing is overruled, no score moves and no mirror needs
    /// recomputing; the user acts on what they see via the existing "I don't have this" correction.
    ///
    /// One-time, so it lives in the migrator rather than the launch path. It's a stored rewrite
    /// rather than a read-time filter because the check needs the résumé and the posting, which the
    /// scoring arithmetic doesn't carry — substring-scanning two documents per requirement on every
    /// read would cost far more than it saves.
    ///
    /// Idempotent: a second pass finds the same spans and writes the same marks. Rows whose résumé or
    /// posting text is gone are skipped rather than guessed at — without both documents the check
    /// can't tell "unsupported" from "the text isn't here to search".
    public func recheckStoredEvidence() throws -> (checked: Int, flagged: Int, skipped: Int) {
        var checked = 0, flagged = 0, skipped = 0
        for record in try modelContext.fetch(FetchDescriptor<JobFitScore>()) {
            guard record.fitStatus == .succeeded,
                  let json = record.fitScoreJSON,
                  let data = json.data(using: .utf8),
                  var dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let assessments = dict["requirement_assessments"] as? [[String: Any]],
                  !assessments.isEmpty
            else { continue }
            let resumeText = record.resume?.text ?? ""
            let posting = record.job?.capture?.cleanedDescription ?? ""
            guard !resumeText.isEmpty, !posting.isEmpty else { skipped += 1; continue }

            let result = EvidenceCheck.apply(to: assessments, resumes: [resumeText], posting: posting)
            checked += 1
            guard result.flagged > 0 else { continue }
            dict["requirement_assessments"] = result.assessments
            guard let updated = try? JSONSerialization.data(withJSONObject: dict),
                  let text = String(data: updated, encoding: .utf8) else { continue }
            record.fitScoreJSON = text
            record.updatedAt = Date()
            flagged += result.flagged
        }
        if flagged > 0 { try modelContext.save() }
        return (checked, flagged, skipped)
    }

    /// Re-evaluate every job's `meetsCriteria` from its already-extracted remote mode + location
    /// against the current location settings. Pure — no LLM calls — so it's the way to apply a
    /// settings change (or the remote-geography rule) to the existing library. Returns the count
    /// changed. Run via JobhuntMigrator.
    public func recomputeMeetsCriteria(
        preferredLocations: String?,
        remoteEligibilityRegions: String? = nil,
        allowRemote: Bool,
        allowHybrid: Bool,
        allowOnsite: Bool,
        filterEnabled: Bool
    ) throws -> Int {
        var changed = 0
        for job in try modelContext.fetch(FetchDescriptor<Job>()) {
            // Repair a missing arrangement the location already states, before judging against it —
            // a null arrangement is treated as on-site, so "United States - Remote" would otherwise
            // keep failing the criteria (job #525).
            let inferred = RemoteTypeInference.infer(remoteType: job.remoteType, location: job.location)
            let arrangementChanged = inferred != job.remoteType
            if arrangementChanged { job.remoteType = inferred }

            let meets = LocationCriteria.meets(
                remoteType: inferred, location: job.location,
                preferredLocations: preferredLocations,
                remoteEligibilityRegions: remoteEligibilityRegions, allowRemote: allowRemote,
                allowHybrid: allowHybrid, allowOnsite: allowOnsite, filterEnabled: filterEnabled
            )
            let verdictChanged = job.meetsCriteria != meets
            if verdictChanged { job.meetsCriteria = meets }

            guard arrangementChanged || verdictChanged else { continue }
            job.updatedAt = Date()
            changed += 1
        }
        if changed > 0 { try modelContext.save() }
        return changed
    }

    /// `recomputeMeetsCriteria` against the location settings as stored. Used by JobhuntMigrator,
    /// which has no `SettingsStore`.
    public func recomputeMeetsCriteriaFromSettings() throws -> Int {
        let rows = try modelContext.fetch(FetchDescriptor<Setting>())
        let byKey = Dictionary(rows.map { ($0.key, $0.value) }, uniquingKeysWith: { first, _ in first })
        func flag(_ key: String) -> Bool {
            guard let raw = byKey[key] else { return true }
            return raw == "true" || raw == "1"
        }
        return try recomputeMeetsCriteria(
            preferredLocations: combinedPreferredLocations(
                locations: byKey[SettingsKey.preferredLocations],
                metros: byKey[SettingsKey.preferredMetros]
            ),
            remoteEligibilityRegions: byKey[SettingsKey.remoteEligibilityRegions],
            allowRemote: flag(SettingsKey.locationAllowRemote),
            allowHybrid: flag(SettingsKey.locationAllowHybrid),
            allowOnsite: flag(SettingsKey.locationAllowOnsite),
            filterEnabled: flag(SettingsKey.locationFilterEnabled)
        )
    }

    /// Scoring corrections, decoded from the settings row the app writes.
    func storedScoringFeedback() throws -> [ScoringFeedback] {
        let rows = try modelContext.fetch(FetchDescriptor<Setting>())
        guard let json = rows.first(where: { $0.key == SettingsKey.scoringFeedback })?.value,
              let data = json.data(using: .utf8),
              let decoded = try? JSONDecoder().decode([ScoringFeedback].self, from: data)
        else { return [] }
        return decoded
    }

    /// Clear stored `<link rel="canonical">` values that don't identify the posting they're attached
    /// to — search/listing-page canonicals from single-page boards. Ingestion treats a canonical match
    /// as proof two captures are the same posting and rewrites the existing capture in place, so a
    /// canonical shared across postings silently overwrites one job with another's content. Returns
    /// the number cleared. Run via JobhuntMigrator.
    public func repairUntrustworthyCanonicalURLs() throws -> Int {
        var cleared = 0
        for capture in try modelContext.fetch(FetchDescriptor<Capture>()) {
            guard let canonical = capture.canonicalURL, !canonical.isEmpty else { continue }
            guard CanonicalURLPolicy.trustworthyCanonical(canonical, captureURL: capture.url) == nil
            else { continue }
            capture.canonicalURL = nil
            cleared += 1
        }
        if cleared > 0 { try modelContext.save() }
        return cleared
    }

    /// One-time cleanup: delete LLM request attempts whose parent request is gone. Historical orphans
    /// from prunes that predate the cascade delete rule. Returns the number deleted. Run via
    /// JobhuntMigrator.
    @discardableResult
    public func pruneOrphanRequestAttempts() throws -> Int {
        let orphans = try modelContext.fetch(FetchDescriptor<LLMRequestAttempt>())
            .filter { $0.request == nil }
        for orphan in orphans {
            modelContext.delete(orphan)
        }
        if !orphans.isEmpty { try modelContext.save() }
        return orphans.count
    }

    /// Recompute every stored fit score from its saved JSON using the current weights/penalty
    /// model — no LLM calls (Electron parity: rescore.js). Returns the count updated.
    public func recomputeAllFitScores() throws -> Int {
        // User corrections are applied when gaps are rebuilt, so a recompute propagates a newly
        // flagged requirement to every stored score without spending an LLM call.
        let feedback = try storedScoringFeedback()
        let allScores = try modelContext.fetch(FetchDescriptor<JobFitScore>())
        var updated = 0
        var affectedJobIDs = Set<String>()
        for record in allScores {
            guard record.fitStatus == .succeeded,
                  let json = record.fitScoreJSON,
                  let result = FitScorer.rescoreFromJSON(
                      json, feedback: feedback, jobNumber: record.job?.jobNumber
                  ) else { continue }
            // Preserve explanation fields (dimensions/rationales); overlay recomputed scores.
            if let data = json.data(using: .utf8),
               let rawDict = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let merged = FitScorer.buildMergedJSON(result: result, rawLLMDict: rawDict) {
                record.fitScoreJSON = merged
            }
            record.fitScore = result.overall
            record.updatedAt = Date()
            updated += 1
            if let job = record.job { affectedJobIDs.insert(job.id) }
        }
        guard updated > 0 else { return 0 }
        let jobs = try modelContext.fetch(FetchDescriptor<Job>())
        for job in jobs where affectedJobIDs.contains(job.id) {
            recomputeJobFitSummary(job)
        }
        try modelContext.save()
        return updated
    }

    /// How many stored requirement assessments each correction currently matches, keyed by its id.
    ///
    /// A correction is a phrase match against requirement text the *model* wrote, so re-scoring can
    /// silently orphan one: three of six live rules stopped matching anything after a re-score
    /// reworded a requirement (a trailing period; a period changed to an em dash). Nothing surfaced
    /// that, so a correction the user believed was in force had quietly stopped applying. Surfacing
    /// the count also exposes the opposite failure — a phrase matching far more than intended.
    ///
    /// O(rules × assessments) over a few hundred jobs, which is imperceptible at this scale.
    /// What a *candidate* correction would hit, measured before it's saved.
    ///
    /// The sheet previously guessed with a length heuristic ("under 5 characters is probably broad"),
    /// which is both wrong and unhelpful: `IDE` is three characters and was force-crediting 359
    /// requirements across 124 jobs, while `PCI DSS` is seven and hits exactly what it should. Reach
    /// is an empirical property of the corpus, not of the string's length, so measure it.
    public func scoringFeedbackMatchPreview(
        phrase: String,
        kind: ScoringFeedback.Kind,
        jobNumber: Int?
    ) throws -> FeedbackMatchPreview {
        var matchingRequirements = 0
        var totalRequirements = 0
        var matchingJobs = Set<Int>()
        var totalJobs = Set<Int>()

        for record in try modelContext.fetch(FetchDescriptor<JobFitScore>()) {
            guard record.fitStatus == .succeeded,
                  let json = record.fitScoreJSON,
                  let data = json.data(using: .utf8),
                  let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let assessments = dict["requirement_assessments"] as? [[String: Any]] else { continue }
            let recordJob = record.job?.jobNumber
            if let recordJob { totalJobs.insert(recordJob) }
            // A job-specific rule can only ever reach its own posting, so scoring the whole corpus
            // against it would overstate the blast radius.
            let inScope = kind != .jobSpecific || recordJob == jobNumber
            for item in assessments {
                guard let requirement = item["requirement"] as? String else { continue }
                totalRequirements += 1
                guard inScope, ScoringFeedback.matches(phrase: phrase, in: requirement) else { continue }
                matchingRequirements += 1
                if let recordJob { matchingJobs.insert(recordJob) }
            }
        }
        return FeedbackMatchPreview(
            matchingRequirements: matchingRequirements,
            matchingJobs: matchingJobs.count,
            totalRequirements: totalRequirements,
            totalJobs: totalJobs.count
        )
    }

    public func scoringFeedbackMatchCounts(_ feedback: [ScoringFeedback]) throws -> [String: Int] {
        var counts: [String: Int] = feedback.reduce(into: [:]) { $0[$1.id] = 0 }
        guard !feedback.isEmpty else { return counts }
        for record in try modelContext.fetch(FetchDescriptor<JobFitScore>()) {
            guard record.fitStatus == .succeeded,
                  let json = record.fitScoreJSON,
                  let data = json.data(using: .utf8),
                  let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let assessments = dict["requirement_assessments"] as? [[String: Any]] else { continue }
            let jobNumber = record.job?.jobNumber
            for item in assessments {
                guard let requirement = item["requirement"] as? String else { continue }
                for entry in feedback {
                    // A job-specific rule only ever applies to its own posting.
                    if entry.kind == .jobSpecific, entry.jobNumber != jobNumber { continue }
                    if ScoringFeedback.matches(phrase: entry.phrase, in: requirement) {
                        counts[entry.id, default: 0] += 1
                    }
                }
            }
        }
        return counts
    }

    /// Delete all JobFitScore records for a resume and reset denormalized fit fields on affected jobs.
    /// Jobs whose score against this résumé no longer reflects its current text — i.e. what a
    /// re-score would cover. Non-destructive: the old scores stay, marked stale for display.
    public func staleFitJobIDs(forResumeID resumeID: String) throws -> [String] {
        let all = try modelContext.fetch(FetchDescriptor<JobFitScore>())
        let resumes = try modelContext.fetch(FetchDescriptor<Resume>(predicate: #Predicate { $0.id == resumeID }))
        guard let resume = resumes.first else { return [] }
        let current = ResumeFingerprint.hash(resume.text)
        return all
            .filter { $0.resume?.id == resumeID && $0.fitStatus == .succeeded && $0.resumeTextHash != current }
            .compactMap { $0.job?.id }
    }

    /// Called when resume text changes so stale scores are not shown as current.
    /// Returns how many fit scores were deleted (so callers can tell the user what was cleared).
    @discardableResult
    public func deleteFitScores(forResumeID resumeID: String) throws -> Int {
        let allScores = try modelContext.fetch(FetchDescriptor<JobFitScore>())
        let toDelete = allScores.filter { $0.resume?.id == resumeID }
        guard !toDelete.isEmpty else { return 0 }

        let affectedJobs = toDelete.compactMap(\.job)
        for score in toDelete {
            modelContext.delete(score)
        }
        try modelContext.save()

        for job in affectedJobs {
            recomputeJobFitSummary(job)
        }
        try modelContext.save()
        return toDelete.count
    }

    /// Create or update a JobFitScore record with fitStatus = .pending.
    public func markFitScorePending(jobID: String, resumeID: String) throws {
        let jobs = try modelContext.fetch(FetchDescriptor<Job>(predicate: #Predicate { $0.id == jobID }))
        guard let job = jobs.first else { return }
        let record = try fitScoreRecord(job: job, resumeID: resumeID)
        record.fitStatus = .pending
        // TASK-519: a queued rescore must not keep its now-stale score driving the job's fit mirror
        // (the mirror picks the best non-nil score and would show .succeeded with the old value).
        record.fitScore = nil
        record.updatedAt = Date()
        recomputeJobFitSummary(job)
        try modelContext.save()
    }

    /// Create or update a JobFitScore record with fitStatus = .running.
    public func markFitScoreRunning(jobID: String, resumeID: String) throws {
        let jobs = try modelContext.fetch(FetchDescriptor<Job>(predicate: #Predicate { $0.id == jobID }))
        guard let job = jobs.first else { return }
        let record = try fitScoreRecord(job: job, resumeID: resumeID)
        record.fitStatus = .running
        // Clear the prior score: a resume that's being re-scored must not keep driving the job's
        // denormalized fit mirror with its now-stale value. Otherwise the headline ("overall fit")
        // can sit above the best *current* resume score until the new score lands — the drift the
        // user sees as e.g. 97 overall vs. a 92 best match. Recompute the mirror from what's left.
        record.fitScore = nil
        record.updatedAt = Date()
        recomputeJobFitSummary(job)
        try modelContext.save()
    }

    /// Create or update a JobFitScore record with fitStatus = .failed, storing the error in fitScoreJSON.
    /// Updates the job-level mirror only when the failed resume is the active resume.
    public func markFitScoreFailed(jobID: String, resumeID: String, errorMessage: String?) throws {
        let jobs = try modelContext.fetch(FetchDescriptor<Job>(predicate: #Predicate { $0.id == jobID }))
        guard let job = jobs.first else { return }
        let record = try fitScoreRecord(job: job, resumeID: resumeID)
        record.fitStatus = .failed
        if let msg = errorMessage {
            // Build via JSONSerialization so control chars/backslashes/quotes in the error message
            // produce valid JSON (hand-escaping only `"` left newlines/tabs unescaped → invalid
            // JSON that FitScoreProjection.parseJSON silently dropped). TASK-472.
            if let data = try? JSONSerialization.data(withJSONObject: ["error": msg]),
               let json = String(data: data, encoding: .utf8) {
                record.fitScoreJSON = json
            } else {
                record.fitScoreJSON = "{\"error\":\"fit scoring failed\"}"
            }
        }
        record.updatedAt = Date()
        // Update job-level mirror only if this is the active resume's failure
        if record.resume?.active == true {
            job.fitStatus = .failed
            job.updatedAt = Date()
        }
        try modelContext.save()
    }

    /// Atomically insert fit LLMRequests and mark corresponding JobFitScores as pending
    /// for a set of (job, resume) pairs. Single save — partial enqueue is impossible.
    public func insertFitBatch(jobIDs: [String], resumeID: String) throws {
        let rid = resumeID
        let resumes = try modelContext.fetch(FetchDescriptor<Resume>(predicate: #Predicate { $0.id == rid }))
        // TASK-452: a missing resume is a real failure — throw so the caller surfaces it. Nothing is
        // inserted before this point, so no partial rows are created.
        guard let resume = resumes.first else { throw FitEnqueueError.resumeNotFound(resumeID) }
        let ids = jobIDs
        let jobs = try modelContext.fetch(FetchDescriptor<Job>(predicate: #Predicate { ids.contains($0.id) }))
        let jobMap = Dictionary(jobs.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        for jobID in jobIDs {
            guard let job = jobMap[jobID] else { continue }
            let req = LLMRequest(requestType: .fit, status: .queued)
            req.job = job
            req.resume = resume
            modelContext.insert(req)
            let record: JobFitScore
            if let existing = job.fitScores.first(where: { $0.resume?.id == resume.id }) {
                record = existing
            } else {
                record = JobFitScore()
                modelContext.insert(record)
                record.job = job
                record.resume = resume
            }
            record.fitStatus = .pending
            record.fitScore = nil // TASK-519: drop a reused record's stale score from the mirror
            record.updatedAt = Date()
            recomputeJobFitSummary(job)
        }
        try modelContext.save()
    }

    /// Queue fit scoring for a job against every active resume, skipping (job, resume)
    /// pairs that already have a queued or running fit request. Returns the count queued.
    /// Mirrors the Electron app's queueFitScoresForAllResumes auto-scoring behavior.
    public func enqueueFitForActiveResumes(jobID: String) throws -> Int {
        let jid = jobID
        let jobs = try modelContext.fetch(FetchDescriptor<Job>(predicate: #Predicate { $0.id == jid }))
        guard let job = jobs.first else { return 0 }
        // A job already flagged as a duplicate doesn't need a fit score — skip it. Guards the manual
        // "score all active resumes" path and any race where detection flagged the job after fit was
        // requested, in addition to the post-extraction auto-enqueue (TASK-611).
        guard job.duplicateOfJobID == nil, job.status != .duplicate else { return 0 }
        let activeResumes = try modelContext.fetch(FetchDescriptor<Resume>(predicate: #Predicate { $0.active == true }))
        guard !activeResumes.isEmpty else { return 0 }

        // Resume IDs that already have an in-flight fit request for this job (avoid duplicates).
        let inflight = try modelContext
            .fetch(FetchDescriptor<LLMRequest>(predicate: #Predicate { $0.finishedAt == nil }))
        let busyResumeIDs = Set(
            inflight
                .filter {
                    $0.requestType == .fit && $0.job?.id == jid && ($0.status == .queued || $0.status == .running)
                }
                .compactMap { $0.resume?.id }
        )

        var queued = 0
        for resume in activeResumes where !busyResumeIDs.contains(resume.id) {
            let req = LLMRequest(requestType: .fit, status: .queued)
            req.job = job
            req.resume = resume
            modelContext.insert(req)
            let record: JobFitScore
            if let existing = job.fitScores.first(where: { $0.resume?.id == resume.id }) {
                record = existing
            } else {
                record = JobFitScore()
                modelContext.insert(record)
                record.job = job
                record.resume = resume
            }
            record.fitStatus = .pending
            record.fitScore = nil // TASK-519: drop a reused record's stale score from the mirror
            record.updatedAt = Date()
            queued += 1
        }
        if queued > 0 {
            recomputeJobFitSummary(job)
            try modelContext.save()
        }
        return queued
    }

    /// Error recorded on a job whose extraction mirror outlived the request that backed it.
    public static let orphanedExtractionError =
        "Extraction never ran — its queued request was cancelled or removed. Re-run extraction to try again."

    /// Reconcile jobs stuck at `.pending`/`.running` extraction with no in-flight (queued/running)
    /// extract request backing them — the extraction-side twin of `reconcileOrphanedFitScores`.
    /// `resetExtraction` and the recapture path both clear the extracted fields and set `.pending`
    /// *before* queuing the request, and cancelling or deleting that request (or losing it to a
    /// failed enqueue) left the job showing "Queued"/"Extracting" forever with every extracted field
    /// blank and nothing left to run. Moves those orphans to `.failed` with a descriptive error so
    /// they surface as re-runnable instead of silently stalling.
    ///
    /// Deliberately does NOT auto-requeue: a stranded job may have a settled fit score, and
    /// re-extraction discards it (`enqueueFitForActiveResumes` resets the record before re-scoring).
    /// Re-running is the user's call.
    @discardableResult
    public func reconcileOrphanedExtractions() throws -> Int {
        let inflight = try modelContext.fetch(
            FetchDescriptor<LLMRequest>(predicate: #Predicate { $0.finishedAt == nil })
        )
        let backed = Set(
            inflight
                .filter { $0.requestType == .extract && ($0.status == .queued || $0.status == .running) }
                .compactMap { $0.job?.id }
        )

        var fixed = 0
        for job in try modelContext.fetch(FetchDescriptor<Job>())
            where job.extractionStatus == .pending || job.extractionStatus == .running {
            if backed.contains(job.id) { continue } // a live request still backs it
            job.extractionStatus = .failed
            job.extractionError = Self.orphanedExtractionError
            job.updatedAt = Date()
            fixed += 1
        }
        guard fixed > 0 else { return 0 }
        try modelContext.save()
        return fixed
    }

    /// Reconcile fit records stuck `.running`/`.pending` with no in-flight (queued/running) fit
    /// request backing them — the state left behind when a fit request is cancelled or deleted
    /// (TASK-527). Without this the job's fit mirror is pinned at "Scoring…" forever. Resets the
    /// orphans to `.none` (no settled score, no live request) and recomputes affected job mirrors.
    /// Returns the number reconciled. Backed records (a queued/running request still exists, e.g.
    /// after a reset) are left alone so they re-run.
    @discardableResult
    public func reconcileOrphanedFitScores() throws -> Int {
        let inflight = try modelContext.fetch(
            FetchDescriptor<LLMRequest>(predicate: #Predicate { $0.finishedAt == nil })
        )
        let backed = Set(
            inflight
                .filter { $0.requestType == .fit && ($0.status == .queued || $0.status == .running) }
                .compactMap { req -> String? in
                    guard let jid = req.job?.id, let rid = req.resume?.id else { return nil }
                    return "\(jid)|\(rid)"
                }
        )

        let scores = try modelContext.fetch(FetchDescriptor<JobFitScore>())
        var affectedJobIDs = Set<String>()
        var fixed = 0
        for score in scores where score.fitStatus == .running || score.fitStatus == .pending {
            guard let jid = score.job?.id, let rid = score.resume?.id else { continue }
            if backed.contains("\(jid)|\(rid)") { continue } // a live request still backs it
            score.fitStatus = FitStatus.none
            score.fitScore = nil
            score.updatedAt = Date()
            affectedJobIDs.insert(jid)
            fixed += 1
        }
        guard fixed > 0 else { return 0 }
        for job in try modelContext.fetch(FetchDescriptor<Job>()) where affectedJobIDs.contains(job.id) {
            recomputeJobFitSummary(job)
        }
        try modelContext.save()
        return fixed
    }

    // MARK: - Off-actor LLM work boundary (TASK-526)

    //
    // The queue runs provider calls on the QueueActor; it must never read or mutate a live SwiftData
    // @Model fetched from this @ModelActor (models aren't Sendable, and a lazy relationship faulted
    // off-actor is a data race). These helpers do all model access ON the store actor and hand back
    // only Sendable snapshots / scalars, or take ids and do the linking internally.

    /// LLM-queue status tallies, counted on the store actor and returned as Sendable scalars (used by
    /// the diagnostics report — the menu/Help path has no SwiftData `@Query` to count from).
    public func llmQueueCounts() throws -> LLMQueueCounts {
        let all = try modelContext.fetch(FetchDescriptor<LLMRequest>())
        return LLMQueueCounts(
            queued: all.count(where: { $0.status == .queued }),
            running: all.count(where: { $0.status == .running }),
            failed: all.count(where: { $0.status == .failed || $0.status == .retryExhausted })
        )
    }

    /// The (Sendable) status of a request, read on the store actor.
    public func requestStatus(id: String) throws -> LLMRequestStatus? {
        let id = id
        return try modelContext.fetch(
            FetchDescriptor<LLMRequest>(predicate: #Predicate { $0.id == id })
        ).first?.status
    }

    /// Build the extraction snapshot on the store actor (so the live Job/Capture relationship is never
    /// read off-actor). Returns nil if the job no longer exists.
    public func extractionSnapshot(forJobID jobID: String) throws -> JobExtractionSnapshot? {
        let jid = jobID
        let jobs = try modelContext.fetch(FetchDescriptor<Job>(predicate: #Predicate { $0.id == jid }))
        guard let job = jobs.first else { return nil }
        return JobExtractionSnapshot(
            captureURL: job.capture?.url ?? "",
            captureCanonicalURL: job.capture?.canonicalURL,
            capturePageTitle: job.capture?.pageTitle ?? "",
            captureCleanedDescription: job.capture?.cleanedDescription,
            captureVisibleText: job.capture?.visibleText,
            captureSelectedText: job.capture?.selectedText
        )
    }

    /// Sendable inputs for a fit run, built on the store actor.
    public struct FitInputs: Sendable {
        public let job: JobFitSnapshot
        /// Empty when the resume has no usable text.
        public let resumeText: String
        /// False when the resume row no longer exists (vs. exists-but-empty).
        public let resumeExists: Bool
    }

    /// Build fit inputs on the store actor. Returns nil if the job no longer exists.
    public func fitInputs(forJobID jobID: String, resumeID: String) throws -> FitInputs? {
        let jid = jobID
        let rid = resumeID
        let jobs = try modelContext.fetch(FetchDescriptor<Job>(predicate: #Predicate { $0.id == jid }))
        guard let job = jobs.first else { return nil }
        let resume = try modelContext.fetch(
            FetchDescriptor<Resume>(predicate: #Predicate { $0.id == rid })
        ).first
        return FitInputs(
            job: JobFitSnapshot(
                title: job.title, company: job.company, seniority: job.seniority,
                extractedJSON: job.extractedJSON, extractionModel: job.extractionModel
            ),
            resumeText: resume?.text ?? "",
            resumeExists: resume != nil
        )
    }

    /// Commit the user-visible extraction result, request state, attempt provenance, and timeline
    /// event together. Returning false means the request was cancelled before the commit began.
    func commitExtractionSuccess(_ result: ExtractionResult, metadata: LLMCompletionMetadata) throws -> Bool {
        let requestID = metadata.requestID
        guard let request = try modelContext.fetch(
            FetchDescriptor<LLMRequest>(predicate: #Predicate { $0.id == requestID })
        ).first else {
            throw BackgroundStoreError.notFound(requestID)
        }
        guard request.status == .running else { return false }

        let jobID = metadata.jobID
        guard let job = try modelContext.fetch(
            FetchDescriptor<Job>(predicate: #Predicate { $0.id == jobID })
        ).first else {
            throw BackgroundStoreError.notFound(jobID)
        }

        let overrides = manualFieldOverrideSet(job.manualFieldOverridesJSON)
        job.extractedJSON = result.extractedJSON
        if !overrides.contains("title") { job.title = result.title }
        if !overrides.contains("company") { job.company = result.company }
        if !overrides.contains("location") { job.location = result.location }
        if !overrides.contains("remoteType") { job.remoteType = result.remoteType }
        if !overrides.contains("salaryMin") { job.salaryMin = result.salaryMin }
        if !overrides.contains("salaryMax") { job.salaryMax = result.salaryMax }
        if !overrides.contains("salaryHourlyMin") { job.salaryHourlyMin = result.salaryHourlyMin }
        if !overrides.contains("salaryHourlyMax") { job.salaryHourlyMax = result.salaryHourlyMax }
        if !overrides.contains("salaryCurrency") { job.salaryCurrency = result.salaryCurrency }
        if !overrides.contains("salaryNote") { job.salaryNote = result.salaryNote }
        if !overrides.contains("employmentType") { job.employmentType = result.employmentType }
        // Normalize on the way in as well as constraining the prompt: the model still returns the
        // posting's own wording often enough, and one canonical value is what the fit-scoring prompt
        // and any future filter both depend on.
        if !overrides.contains("seniority") {
            job.seniority = SeniorityNormalizer.normalize(result.seniority)
        }
        if !overrides.contains("applicationURL") { job.applicationURL = result.applicationURL }
        job.extractionConfidence = result.extractionConfidence
        job.meetsCriteria = result.meetsCriteria
        job.extractionModel = result.extractionModel
        job.extractionStatus = .succeeded
        job.extractionError = nil
        job.extractedAt = metadata.finishedAt
        // "Unread" means the USER hasn't seen this job — not that the extractor ran.
        //
        // This was set unconditionally, so re-extracting a job you had already opened marked it new
        // again. Re-running the failed extractions lit up sixteen rows the user had demonstrably
        // read, one of them last opened three weeks earlier. It matters more than the noise suggests:
        // a bulk re-extraction after a prompt change would flag hundreds of already-triaged jobs.
        //
        // A job that has never been opened stays unread — the first extraction is genuinely news.
        if job.lastOpenedAt == nil {
            job.unread = true
        }
        job.updatedAt = metadata.finishedAt

        try insertAttempt(
            requestID: requestID,
            jobID: jobID,
            requestType: .extract,
            attempt: metadata.attempt,
            status: .succeeded,
            modelRequested: metadata.modelRequested,
            modelReturned: result.extractionModel,
            responseFormat: result.responseFormat.wireValue,
            baseURL: metadata.baseURL,
            startedAt: metadata.startedAt,
            finishedAt: metadata.finishedAt,
            durationMs: metadata.durationMs,
            promptChars: result.promptChars,
            responseChars: result.responseChars,
            promptTokens: result.promptTokens,
            completionTokens: result.completionTokens
        )

        request.status = .succeeded
        request.finishedAt = metadata.finishedAt
        request.model = result.extractionModel
        request.error = nil

        let event = JobEvent(eventType: "extraction", note: result.extractionModel)
        event.job = job
        modelContext.insert(event)

        try saveAtomically()
        return true
    }

    /// Commit a fit score, request state, and attempt provenance with one save.
    func commitFitSuccess(
        _ output: FitScoreOutput,
        fitJSON: String?,
        fitModel: String,
        scoredAt: Date,
        resumeID: String,
        metadata: LLMCompletionMetadata
    ) throws -> Bool {
        let requestID = metadata.requestID
        guard let request = try modelContext.fetch(
            FetchDescriptor<LLMRequest>(predicate: #Predicate { $0.id == requestID })
        ).first else {
            throw BackgroundStoreError.notFound(requestID)
        }
        guard request.status == .running else { return false }

        try applyFitScore(
            jobID: metadata.jobID,
            resumeID: resumeID,
            overall: output.score.overall,
            fitJSON: fitJSON,
            model: output.modelReturned,
            scoredAt: scoredAt
        )
        try insertAttempt(
            requestID: requestID,
            jobID: metadata.jobID,
            requestType: .fit,
            attempt: metadata.attempt,
            status: .succeeded,
            modelRequested: fitModel,
            modelReturned: output.modelReturned,
            responseFormat: output.responseFormat.wireValue,
            baseURL: metadata.baseURL,
            startedAt: metadata.startedAt,
            finishedAt: metadata.finishedAt,
            durationMs: metadata.durationMs,
            promptChars: output.promptChars,
            responseChars: output.responseChars,
            promptTokens: output.promptTokens,
            completionTokens: output.completionTokens
        )

        request.status = .succeeded
        request.finishedAt = metadata.finishedAt
        request.model = output.modelReturned
        request.error = nil

        try saveAtomically()
        return true
    }

    /// Create + persist an LLM attempt, linked (by id) to its request and job on the store actor —
    /// so the queue never assigns a live model into a relationship off-actor.
    public func recordAttempt(
        requestID: String,
        jobID: String?,
        requestType: LLMRequestType,
        attempt: Int,
        status: LLMRequestStatus,
        modelRequested: String?,
        modelReturned: String? = nil,
        responseFormat: String? = nil,
        baseURL: String? = nil,
        startedAt: Date,
        finishedAt: Date,
        durationMs: Int? = nil,
        promptChars: Int? = nil,
        responseChars: Int? = nil,
        responsePreview: String? = nil,
        promptTokens: Int? = nil,
        completionTokens: Int? = nil,
        error: String? = nil
    ) throws {
        try insertAttempt(
            requestID: requestID,
            jobID: jobID,
            requestType: requestType,
            attempt: attempt,
            status: status,
            modelRequested: modelRequested,
            modelReturned: modelReturned,
            responseFormat: responseFormat,
            baseURL: baseURL,
            startedAt: startedAt,
            finishedAt: finishedAt,
            durationMs: durationMs,
            promptChars: promptChars,
            responseChars: responseChars,
            responsePreview: responsePreview,
            promptTokens: promptTokens,
            completionTokens: completionTokens,
            error: error
        )
        try modelContext.save()
    }

    private func insertAttempt(
        requestID: String,
        jobID: String?,
        requestType: LLMRequestType,
        attempt: Int,
        status: LLMRequestStatus,
        modelRequested: String?,
        modelReturned: String? = nil,
        responseFormat: String? = nil,
        baseURL: String? = nil,
        startedAt: Date,
        finishedAt: Date,
        durationMs: Int? = nil,
        promptChars: Int? = nil,
        responseChars: Int? = nil,
        responsePreview: String? = nil,
        promptTokens: Int? = nil,
        completionTokens: Int? = nil,
        error: String? = nil
    ) throws {
        let rid = requestID
        let record = LLMRequestAttempt(
            requestType: requestType, attempt: attempt, status: status,
            modelRequested: modelRequested, modelReturned: modelReturned, responseFormat: responseFormat,
            baseURL: baseURL,
            startedAt: startedAt, finishedAt: finishedAt, durationMs: durationMs,
            error: error, responsePreview: responsePreview, promptChars: promptChars, responseChars: responseChars,
            promptTokens: promptTokens, completionTokens: completionTokens
        )
        record.request = try modelContext.fetch(
            FetchDescriptor<LLMRequest>(predicate: #Predicate { $0.id == rid })
        ).first
        if let jobID {
            record.job = try modelContext.fetch(
                FetchDescriptor<Job>(predicate: #Predicate { $0.id == jobID })
            ).first
        }
        modelContext.insert(record)
    }

    /// Append a timeline event to a job, linked on the store actor (TASK-526). No-op if the job is gone.
    /// Append a timeline event to a job, linked on the store actor (TASK-526). Best-effort by default
    /// (a missing job is a no-op) for system events like the extraction timeline entry; pass
    /// `requireJob: true` for user-facing writes (notes) so a deleted job surfaces as an error instead
    /// of silently persisting nothing (TASK-578).
    public func insertJobEvent(
        jobID: String, eventType: String, note: String? = nil,
        occurredAt: Date = Date(), createdAt: Date = Date(), requireJob: Bool = false
    ) throws {
        let jid = jobID
        let jobs = try modelContext.fetch(FetchDescriptor<Job>(predicate: #Predicate { $0.id == jid }))
        guard let job = jobs.first else {
            if requireJob { throw BackgroundStoreError.notFound(jobID) }
            return
        }
        let event = JobEvent(eventType: eventType, note: note, occurredAt: occurredAt, createdAt: createdAt)
        event.job = job
        modelContext.insert(event)
        try modelContext.save()
    }

    /// Create + link a follow-up action to a job by id (TASK-526). Throws `notFound` if the job is
    /// gone — a user-facing write must not silently no-op (TASK-578).
    /// Today's recap, for the optional end-of-day reminder (TASK-623 #11).
    ///
    /// Built here rather than read off the dashboard view: the reminder fires whether or not the
    /// Dashboard has ever been shown, so it can't depend on a view's `@Query`.
    public func todayRecap(now: Date = Date(), calendar: Calendar = .current) throws -> DailyRecap {
        let events = try modelContext.fetch(FetchDescriptor<JobEvent>()).map {
            DashboardMetrics.RecapEvent(
                eventType: $0.eventType, note: $0.note, occurredAt: $0.occurredAt,
                jobID: $0.job?.id, jobNumber: $0.job?.jobNumber,
                company: $0.job?.company, title: $0.job?.title
            )
        }
        let completions = try modelContext.fetch(FetchDescriptor<JobAction>())
            .compactMap(\.completedAt)
        return DashboardMetrics.buildDailyRecap(
            events: events, followUpCompletions: completions, day: now, calendar: calendar
        )
    }

    /// Record what a check concluded about each job (TASK-674).
    ///
    /// Nothing was stored before, so every run started from zero: two runs over an unchanged archive
    /// could report seven gone postings and then four, and neither the user nor the app could say
    /// which of those were new. Recording the verdict — including "couldn't be checked", which is not
    /// the same as "fine" — is what makes runs comparable.
    ///
    /// Deliberately does NOT touch `updatedAt`: a check is something that happened TO the posting
    /// elsewhere, not an edit the user made, and bumping it would reorder every recently-checked job
    /// in a list sorted by last change.
    @discardableResult
    public func recordAvailabilityOutcomes(
        _ outcomes: [AvailabilityOutcome], checkedAt: Date = Date()
    ) throws -> Int {
        guard !outcomes.isEmpty else { return 0 }
        let byID = Dictionary(outcomes.map { ($0.jobID, $0) }, uniquingKeysWith: { _, latest in latest })
        let ids = Set(byID.keys)
        var written = 0
        for job in try modelContext.fetch(FetchDescriptor<Job>()) where ids.contains(job.id) {
            guard let outcome = byID[job.id] else { continue }
            job.availabilityCheckedAt = checkedAt
            job.availabilityVerdict = outcome.verdict.rawValue
            job.availabilityDetail = outcome.detail
            written += 1
        }
        try modelContext.save()
        return written
    }

    /// Jobs whose last check couldn't answer, and could answer if asked again (TASK-673).
    ///
    /// What makes a resumed drain possible: the backlog itself is in memory, so quitting mid-drain
    /// used to throw away everything still owed an answer. The store already knows — `.unverified`
    /// with a retryable reason IS the pending set — it simply was never read back.
    ///
    /// Ordered oldest-checked first, so a resumed drain works on what has been waiting longest rather
    /// than re-asking about postings a run just deferred.
    public func jobsAwaitingAvailabilityAnswer(limit: Int = 500) throws -> [String] {
        // Hoisted: #Predicate can't reach through an enum case.
        let unverified = AvailabilityVerdict.unverified.rawValue
        var descriptor = FetchDescriptor<Job>(
            predicate: #Predicate { $0.availabilityVerdict == unverified },
            sortBy: [SortDescriptor(\.availabilityCheckedAt, order: .forward)]
        )
        descriptor.fetchLimit = limit
        return try modelContext.fetch(descriptor)
            .filter {
                guard let reason = UnverifiedReason.stored($0.availabilityDetail) else { return false }
                return AvailabilityBacklog.retryableReasons.contains(reason)
            }
            .map(\.id)
    }

    /// Sites whose next review date has passed (TASK-503).
    ///
    /// Excluded sites are skipped: the user has said they're done with them, and a reminder about a
    /// site you deliberately shelved is worse than no reminder at all.
    public func dueSiteReviews(now: Date = Date()) throws -> [DueSiteReviews.Item] {
        try modelContext.fetch(FetchDescriptor<Site>())
            .filter { $0.state != .exclude && DueSiteReviews.isDue(nextReviewAt: $0.nextReviewAt, now: now) }
            .map { site in
                DueSiteReviews.Item(
                    id: site.id,
                    name: site.companyName?.isEmpty == false
                        ? (site.companyName ?? site.origin)
                        : (site.pageTitle.isEmpty ? site.origin : site.pageTitle),
                    daysOverdue: site.nextReviewAt.map {
                        DueSiteReviews.daysOverdue(nextReviewAt: $0, now: now)
                    } ?? 0
                )
            }
            .sorted { $0.daysOverdue > $1.daysOverdue }
    }

    /// The jobs with these ids, for a caller that already knows exactly which rows it wants — the
    /// availability drain, which re-asks about a specific batch it couldn't answer for earlier.
    ///
    /// Returns only the rows that still exist: a job deleted between the deferral and the retry is
    /// simply absent, which the caller treats as answered rather than as a batch to keep retrying.
    public func jobs(withIDs ids: [String]) throws -> sending [Job] {
        guard !ids.isEmpty else { return [] }
        let wanted = Set(ids)
        return try modelContext.fetch(FetchDescriptor<Job>()).filter { wanted.contains($0.id) }
    }

    /// Every job as a Spotlight entry (TASK-590). Jobs that can't be linked or named are dropped by
    /// `SpotlightEntry.make` rather than indexed as blanks.
    public func spotlightEntries() throws -> [SpotlightEntry] {
        try modelContext.fetch(FetchDescriptor<Job>()).compactMap { job in
            SpotlightEntry.make(
                jobNumber: job.jobNumber,
                title: job.title,
                company: job.company,
                location: job.location,
                salary: SalaryDisplay.text(
                    min: job.salaryMin, max: job.salaryMax, currency: job.salaryCurrency
                ),
                status: job.status.displayName,
                skills: JobDetailProjection(job: job).skills
            )
        }
    }

    /// Follow-ups that are due right now, flattened for the notifier (TASK-589).
    ///
    /// Filtered in Swift rather than in the `#Predicate`: the snooze rule involves comparing two
    /// optional dates against `now`, the rule is shared with the UI's own due-ness check, and at a
    /// few hundred actions the scan is imperceptible (see the scale convention in CLAUDE.md).
    public func dueFollowUps(now: Date = Date()) throws -> [DueFollowUps.Item] {
        try modelContext.fetch(FetchDescriptor<JobAction>())
            .filter {
                DueFollowUps.isDue(
                    dueDate: $0.dueDate, completedAt: $0.completedAt,
                    snoozedUntil: $0.snoozedUntil, now: now
                )
            }
            // An action with no job can't be opened or described — those are orphans, and the
            // migrator has a mode for pruning them.
            .compactMap { action in
                guard let job = action.job else { return nil }
                return DueFollowUps.Item(
                    id: action.id,
                    jobNumber: job.jobNumber,
                    title: job.title ?? "",
                    company: job.company,
                    note: action.note
                )
            }
    }

    public func insertJobAction(jobID: String, note: String, dueDate: Date) throws {
        let jid = jobID
        let jobs = try modelContext.fetch(FetchDescriptor<Job>(predicate: #Predicate { $0.id == jid }))
        guard let job = jobs.first else { throw BackgroundStoreError.notFound(jobID) }
        let action = JobAction(note: note, dueDate: dueDate)
        action.job = job
        modelContext.insert(action)
        try modelContext.save()
    }

    /// Create + link a contact to a job by id (TASK-526). No-op if the job is gone.
    public func insertContact(jobID: String, name: String, role: String?, email: String?) throws {
        let jid = jobID
        let jobs = try modelContext.fetch(FetchDescriptor<Job>(predicate: #Predicate { $0.id == jid }))
        guard let job = jobs.first else { return }
        let contact = Contact(name: name, role: role, email: email)
        contact.job = job
        modelContext.insert(contact)
        try modelContext.save()
    }

    /// Create or update a job's data-quality review, on the store actor (TASK-526).
    /// Insert or update a job's ESD application evidence (TASK-628), keyed by job id. Blank fields are
    /// stored as nil so "missing" stays authoritative. No-op-safe: overwrites the single evidence row.
    public func upsertApplicationEvidence(_ input: ApplicationEvidenceInput) throws {
        let jid = input.jobID
        var descriptor = FetchDescriptor<ApplicationEvidence>(predicate: #Predicate { $0.jobID == jid })
        descriptor.fetchLimit = 1
        let evidence: ApplicationEvidence
        if let existing = try modelContext.fetch(descriptor).first {
            evidence = existing
        } else {
            evidence = ApplicationEvidence(jobID: jid)
            modelContext.insert(evidence)
        }
        func clean(_ value: String?) -> String? {
            let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines)
            return (trimmed?.isEmpty ?? true) ? nil : trimmed
        }
        evidence.updatedAt = Date()
        evidence.correctedAppliedAt = input.correctedAppliedAt
        evidence.contactMethod = clean(input.contactMethod)
        evidence.contactType = clean(input.contactType)
        evidence.employerWebsiteOrEmail = clean(input.employerWebsiteOrEmail)
        evidence.phone = clean(input.phone)
        evidence.employerAddress = clean(input.employerAddress)
        evidence.city = clean(input.city)
        evidence.state = clean(input.state)
        evidence.jobReferenceNumber = clean(input.jobReferenceNumber)
        evidence.applicationResult = clean(input.applicationResult)
        try modelContext.save()
    }

    // MARK: - Application milestones (TASK-630/501)

    // Referrals, interviews and offers live in `MilestonePersistence` (TASK-686) — the rules pairing
    // each record with its timeline event are subtle enough to be worth reading in one place, rather
    // than interleaved with every other domain that writes through this store.
    //
    // These stay here as the entry points because the transaction does: the persistence functions run
    // on this actor against this context, and the `save()` is this store's, so a milestone write is
    // still one atomic unit with anything else in flight.

    @discardableResult
    public func recordReferralAttempt(_ input: ReferralAttemptInput) throws -> String {
        let id = try MilestonePersistence.recordReferralAttempt(input, in: modelContext)
        try modelContext.save()
        return id
    }

    public func deleteReferralAttempt(id: String) throws {
        guard try MilestonePersistence.deleteReferralAttempt(id: id, in: modelContext) else { return }
        try modelContext.save()
    }

    public func setReferralNotApplicable(jobID: String, _ notApplicable: Bool) throws {
        try MilestonePersistence.setReferralNotApplicable(jobID: jobID, notApplicable, in: modelContext)
        try modelContext.save()
    }

    @discardableResult
    public func recordInterview(_ input: InterviewInput) throws -> String {
        let id = try MilestonePersistence.recordInterview(input, in: modelContext)
        try modelContext.save()
        return id
    }

    public func deleteInterview(id: String) throws {
        guard try MilestonePersistence.deleteInterview(id: id, in: modelContext) else { return }
        try modelContext.save()
    }

    @discardableResult
    public func recordOffer(_ input: OfferInput) throws -> String {
        let id = try MilestonePersistence.recordOffer(input, in: modelContext)
        try modelContext.save()
        return id
    }

    public func deleteOffer(id: String) throws {
        guard try MilestonePersistence.deleteOffer(id: id, in: modelContext) else { return }
        try modelContext.save()
    }

    /// Delete every interview and offer belonging to a job — cascaded on job delete, since these are
    /// keyed by `jobID` with no relationship.
    public func deleteMilestones(jobID: String) throws {
        guard try MilestonePersistence.deleteMilestones(jobID: jobID, in: modelContext) else { return }
        try modelContext.save()
    }

    /// Delete every referral attempt (and N/A marker) belonging to a job.
    public func deleteReferralAttempts(jobID: String) throws {
        guard try MilestonePersistence.deleteReferralAttempts(jobID: jobID, in: modelContext) else { return }
        try modelContext.save()
    }

    /// Delete referral attempts whose job no longer exists. Returns the number removed.
    @discardableResult
    public func pruneOrphanReferralAttempts() throws -> Int {
        let removed = try MilestonePersistence.pruneOrphanReferralAttempts(in: modelContext)
        if removed > 0 { try modelContext.save() }
        return removed
    }

    public func upsertDataQualityReview(jobID: String, note: String) throws {
        let jid = jobID
        let jobs = try modelContext.fetch(FetchDescriptor<Job>(predicate: #Predicate { $0.id == jid }))
        guard let job = jobs.first else { return }
        if let existing = job.qualityReview {
            existing.reviewedAt = Date()
            existing.note = note
        } else {
            let review = DataQualityReview(reviewedAt: Date(), note: note)
            review.job = job
            modelContext.insert(review)
        }
        try modelContext.save()
    }

    /// Delete a job's data-quality review, on the store actor (TASK-526). No-op if absent.
    public func clearDataQualityReview(jobID: String) throws {
        let jid = jobID
        let jobs = try modelContext.fetch(FetchDescriptor<Job>(predicate: #Predicate { $0.id == jid }))
        guard let job = jobs.first, let review = job.qualityReview else { return }
        modelContext.delete(review)
        try modelContext.save()
    }

    /// Insert extraction/fit requests for a set of jobs, linked on the store actor (TASK-526). Skips
    /// jobs that already have a queued/running request for the mode. Returns whether anything was
    /// inserted (so the caller can decide whether to kick the drain).
    public func insertRequests(jobIDs: [String], mode: LLMRequestType) throws -> Bool {
        guard !jobIDs.isEmpty else { return false }
        let ids = jobIDs
        let jobs = try modelContext.fetch(FetchDescriptor<Job>(predicate: #Predicate { ids.contains($0.id) }))
        let jobMap = Dictionary(jobs.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let existing = try modelContext.fetch(
            FetchDescriptor<LLMRequest>(predicate: #Predicate { $0.finishedAt == nil })
        )
        let alreadyActive = Set(
            existing
                .filter { ($0.status == .queued || $0.status == .running) && $0.requestType == mode }
                .compactMap { $0.job?.id }
                .filter { ids.contains($0) }
        )
        var inserted = false
        for jobID in jobIDs {
            guard let job = jobMap[jobID], !alreadyActive.contains(jobID) else { continue }
            let req = LLMRequest(requestType: mode, status: .queued)
            req.job = job
            modelContext.insert(req)
            inserted = true
        }
        if inserted { try modelContext.save() }
        return inserted
    }

    /// Recompute every job's fit mirror from the best-scoring resume across resumes.
    /// `activeResumeID` is retained for source compatibility but no longer affects the mirror
    /// (the mirror is best-across-resumes, not active-resume-specific).
    public func recomputeJobFitMirrors(activeResumeID _: String?) throws {
        let jobs = try modelContext.fetch(FetchDescriptor<Job>())
        for job in jobs {
            recomputeJobFitSummary(job)
        }
        try modelContext.save()
    }

    /// Count of unresolved duplicate REVIEW pairs — the same set the Duplicates screen shows. Computes
    /// live and persists/marks NOTHING (TASK-624: duplicates are only ever resolved by explicit user
    /// action in the review screen).
    public func reviewablePairCount() throws -> Int {
        let jobs = try modelContext.fetch(FetchDescriptor<Job>())
        let decisions = try modelContext.fetch(FetchDescriptor<DuplicateDecision>())
        return DuplicateDetector.unresolvedPairCount(jobs: jobs, decisions: decisions)
    }

    /// Run domain-duplicate detection across all jobs and persist results: flag each detected
    /// candidate with duplicateOfJobID + confidence + `.duplicate` status, and log a
    /// `duplicate_detected` event. Skips pairs already resolved via DuplicateDecision.
    /// (Electron parity: detectDomainDuplicateJobs after markExtractionSucceeded.) Returns count flagged.
    /// TASK-624: no longer called by the app — duplicates are never auto-marked. Retained for tooling.
    public func detectAndPersistDomainDuplicates() throws -> Int {
        let jobs = try modelContext.fetch(FetchDescriptor<Job>())
        let snapshots = jobs.compactMap { job -> JobSnapshot? in
            guard let capture = job.capture else { return nil }
            return JobSnapshot(job: job, capture: capture)
        }
        let decisions = try modelContext.fetch(FetchDescriptor<DuplicateDecision>())
        let resolvedHashes = Set(decisions.map(\.cleanedHash))
        let pairs = DuplicateDetector().duplicateGroups(snapshots: snapshots, resolvedHashes: resolvedHashes)
        guard !pairs.isEmpty else { return 0 }

        let jobIndex = Dictionary(jobs.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        var flagged = 0
        for pair in pairs {
            // Only AUTO-mark DEFINITIVE matches — the same posting (identical cleaned text, or the same
            // ATS posting id). Fuzzy heuristic matches (similar title / same-company) are surfaced in the
            // Duplicates review screen for the user to confirm; auto-marking them wrongly hid legitimately
            // distinct jobs, e.g. a specialization of the same base title (TASK-622).
            guard pair.kind == .exactHash || pair.kind == .atsPostingID else { continue }
            guard let candidate = jobIndex[pair.candidate.id] else { continue }
            if candidate.duplicateOfJobID == pair.original.id { continue } // already flagged
            candidate.duplicateOfJobID = pair.original.id
            candidate.duplicateConfidence = pair.confidence
            if candidate.status != .duplicate { candidate.status = .duplicate }
            candidate.updatedAt = Date()
            let originalNum = pair.original.jobNumber.map { "#\($0)" } ?? "another job"
            let event = JobEvent(
                eventType: "duplicate_detected",
                note: "Flagged as a possible duplicate of \(originalNum) — \(pair.reason)"
            )
            event.job = candidate
            modelContext.insert(event)
            flagged += 1
        }
        if flagged > 0 { try modelContext.save() }
        return flagged
    }

    /// TASK-622 recovery: un-mark jobs that were auto-marked `.duplicate` by the FUZZY heuristic path
    /// (before auto-marking was restricted to definitive matches). A job is recovered when its most
    /// recent `duplicate_detected` event is NOT a definitive (same-ATS-id / exact-hash) match. Restores
    /// its status from its last `status` timeline event (default `.pursuing`), clears the duplicate
    /// flag, and logs a status event. Idempotent (recovered jobs are no longer `.duplicate`). Returns
    /// the number recovered.
    @discardableResult
    public func unmarkHeuristicDuplicates() throws -> Int {
        let marked = try modelContext.fetch(FetchDescriptor<Job>()).filter {
            $0.status == .duplicate && !($0.duplicateOfJobID?.isEmpty ?? true)
        }
        var recovered = 0
        for job in marked {
            let dupEvents = job.events.filter { $0.eventType == "duplicate_detected" }
                .sorted { $0.createdAt < $1.createdAt }
            guard let latest = dupEvents.last else { continue }
            let note = (latest.note ?? "").lowercased()
            // Keep definitive flags (the same posting); recover everything fuzzy.
            if note.contains("same ats posting id") || note.contains("exact cleaned-description hash") { continue }

            let restored = priorStatusBeforeDuplicate(job)
            job.duplicateOfJobID = nil
            job.duplicateConfidence = nil
            job.status = restored
            job.updatedAt = Date()
            let event = JobEvent(
                eventType: "status",
                note: "Restored to \(restored.rawValue) — un-marked a heuristic duplicate flag (TASK-622)"
            )
            event.job = job
            modelContext.insert(event)
            recovered += 1
        }
        if recovered > 0 { try modelContext.save() }
        return recovered
    }

    /// The job's last real status before it was auto-marked `.duplicate` (which didn't log a status
    /// event), parsed from the most recent "Status changed from X to Y" event; `.pursuing` if unknown.
    private func priorStatusBeforeDuplicate(_ job: Job) -> JobStatus {
        let statusEvents = job.events.filter { $0.eventType == "status" }.sorted { $0.createdAt < $1.createdAt }
        for event in statusEvents.reversed() {
            guard let note = event.note, let toRange = note.range(of: "to ", options: .backwards) else { continue }
            let target = note[toRange.upperBound...].trimmingCharacters(in: .whitespaces)
            if let status = JobStatus(rawValue: target), status != .duplicate { return status }
        }
        return .pursuing
    }

    /// Incremental duplicate check for a SINGLE just-extracted job. If it looks like a duplicate of an
    /// already-captured job, flag it (duplicateOfJobID + confidence + `.duplicate` status + a
    /// `duplicate_detected` event) and return true. Runs after extraction and BEFORE fit scoring so a
    /// duplicate never wastes a fit LLM call (TASK-611). Cheaper than `detectAndPersistDomainDuplicates`
    /// — it compares this one job against same-title/same-hash jobs, not every pair. Returns false when
    /// the job is missing, not yet extracted, already a duplicate, or not a duplicate of anything.
    public func detectDuplicateForJob(jobID: String) throws -> Bool {
        let jid = jobID
        let matches = try modelContext.fetch(FetchDescriptor<Job>(predicate: #Predicate { $0.id == jid }))
        guard let job = matches.first, let capture = job.capture,
              job.extractionStatus == .succeeded,
              job.duplicateOfJobID == nil, job.status != .duplicate else {
            return false
        }
        let candidate = JobSnapshot(job: job, capture: capture)

        let corpus = try modelContext.fetch(FetchDescriptor<Job>()).compactMap { other -> JobSnapshot? in
            guard other.id != jid, let cap = other.capture else { return nil }
            return JobSnapshot(job: other, capture: cap)
        }
        let decisions = try modelContext.fetch(FetchDescriptor<DuplicateDecision>())
        let resolvedHashes = Set(decisions.map(\.cleanedHash))

        guard let pair = DuplicateDetector().duplicatePairForCandidate(
            candidate, among: corpus, resolvedHashes: resolvedHashes
        ) else { return false }
        // Only auto-mark a DEFINITIVE match (same posting); a fuzzy candidate stays a real job to be
        // fit-scored and surfaced in the Duplicates review screen for the user to confirm (TASK-622).
        guard pair.kind == .exactHash || pair.kind == .atsPostingID else { return false }

        job.duplicateOfJobID = pair.original.id
        job.duplicateConfidence = pair.confidence
        job.status = .duplicate
        job.updatedAt = Date()
        let originalNum = pair.original.jobNumber.map { "#\($0)" } ?? "another job"
        let event = JobEvent(
            eventType: "duplicate_detected",
            note: "Flagged as a possible duplicate of \(originalNum) — \(pair.reason)"
        )
        event.job = job
        modelContext.insert(event)
        try modelContext.save()
        return true
    }

    /// Outcome of folding one job into another.
    public struct MergeJobResult: Sendable {
        public let keptJobNumber: Int
        public let removedJobNumber: Int
        /// Field names filled in on the kept job from the removed one.
        public let fieldsCopied: [String]
    }

    /// Fold a duplicate job into the one being kept, then delete the duplicate.
    ///
    /// For the case this exists to fix: a cosmetic URL difference forked a recapture into a second
    /// job, so the newer job holds a good extraction while the original holds the status, notes and
    /// fit score built up against it. Only fills fields the kept job is MISSING — a manually
    /// overridden or already-populated field is never overwritten — and never touches the kept job's
    /// status, notes or fit scores. The kept job's capture is also left alone: the duplicate's
    /// capture is deleted with it, so merge only when the two describe the same posting.
    ///
    /// Extraction provenance (`extractedJSON`/model/confidence/`extractedAt`/status) moves as one
    /// unit, and only when the kept job has no extraction of its own — a half-copied provenance
    /// would misattribute which model produced which field.
    public func mergeJob(from sourceNumber: Int, into targetNumber: Int) throws -> MergeJobResult {
        guard sourceNumber != targetNumber else {
            throw BackgroundStoreError.notFound("cannot merge job #\(sourceNumber) into itself")
        }
        let src = sourceNumber, dst = targetNumber
        let jobs = try modelContext.fetch(
            FetchDescriptor<Job>(predicate: #Predicate { $0.jobNumber == src || $0.jobNumber == dst })
        )
        guard let source = jobs.first(where: { $0.jobNumber == src }) else {
            throw BackgroundStoreError.notFound("job #\(src)")
        }
        guard let target = jobs.first(where: { $0.jobNumber == dst }) else {
            throw BackgroundStoreError.notFound("job #\(dst)")
        }

        let overrides = manualFieldOverrideSet(target.manualFieldOverridesJSON)
        var copied: [String] = []
        /// Copy one field when the target lacks it and the user hasn't manually set it.
        func fill(_ name: String, _ keyPath: ReferenceWritableKeyPath<Job, (some Any)?>) {
            guard target[keyPath: keyPath] == nil, !overrides.contains(name),
                  let value = source[keyPath: keyPath] else { return }
            target[keyPath: keyPath] = value
            copied.append(name)
        }
        fill("company", \.company)
        fill("title", \.title)
        fill("location", \.location)
        fill("remoteType", \.remoteType)
        fill("salaryMin", \.salaryMin)
        fill("salaryMax", \.salaryMax)
        fill("salaryHourlyMin", \.salaryHourlyMin)
        fill("salaryHourlyMax", \.salaryHourlyMax)
        fill("salaryCurrency", \.salaryCurrency)
        fill("salaryNote", \.salaryNote)
        fill("employmentType", \.employmentType)
        fill("seniority", \.seniority)
        fill("applicationURL", \.applicationURL)
        fill("meetsCriteria", \.meetsCriteria)

        if target.extractedJSON == nil, source.extractedJSON != nil {
            target.extractedJSON = source.extractedJSON
            target.extractionModel = source.extractionModel
            target.extractionConfidence = source.extractionConfidence
            target.extractedAt = source.extractedAt
            target.extractionStatus = source.extractionStatus
            target.extractionError = nil
            copied.append("extractedJSON")
        }
        target.updatedAt = Date()

        let event = JobEvent(
            eventType: "merge",
            note: "Merged job #\(src) into this job"
                + (copied.isEmpty ? " (no missing fields to fill)" : " — filled \(copied.joined(separator: ", "))")
        )
        event.job = target
        modelContext.insert(event)
        modelContext.delete(source) // cascades to its capture, events, fit scores and requests
        try modelContext.save()

        return MergeJobResult(keptJobNumber: dst, removedJobNumber: src, fieldsCopied: copied)
    }

    /// Record (or update) a duplicate decision so a resolved pair does not resurface in detection.
    public func upsertDuplicateDecision(cleanedHash: String, decision: String, keepJobID: String?) throws {
        let ch = cleanedHash
        let existing = try modelContext
            .fetch(FetchDescriptor<DuplicateDecision>(predicate: #Predicate { $0.cleanedHash == ch }))
        if let row = existing.first {
            row.decision = decision
            row.keepJobID = keepJobID
            row.decidedAt = Date()
        } else {
            modelContext.insert(DuplicateDecision(cleanedHash: cleanedHash, decision: decision, keepJobID: keepJobID))
        }
        try modelContext.save()
    }

    private func fitScoreRecord(job: Job, resumeID: String) throws -> JobFitScore {
        if let existing = job.fitScores.first(where: { $0.resume?.id == resumeID }) {
            return existing
        }
        let record = JobFitScore()
        modelContext.insert(record)
        record.job = job
        let resumes = try modelContext.fetch(FetchDescriptor<Resume>(predicate: #Predicate { $0.id == resumeID }))
        record.resume = resumes.first
        return record
    }

    /// Atomically dedup-check, assign job number, and insert Capture + Job + extraction LLMRequest
    /// in a single modelContext.save(). No other BackgroundStore call can interleave mid-operation.
    public func insertCaptureAtomically(_ input: AtomicIngestInput) throws -> AtomicIngestResult {
        // Raw hash: exact duplicate — fetch only the matching row (O(1) via predicate)
        let rawHashValue = input.rawHash
        var rawDescriptor = FetchDescriptor<Capture>(predicate: #Predicate { $0.rawHash == rawHashValue })
        rawDescriptor.fetchLimit = 1
        if let existing = try modelContext.fetch(rawDescriptor).first,
           let existingJob = existing.job {
            return AtomicIngestResult(
                captureID: existing.id,
                jobNumber: existingJob.jobNumber ?? 0,
                isDuplicate: true
            )
        }

        // Re-capture: same URL (or canonical URL) but changed content — identical content already
        // returned above. Update the existing capture/job in place, reset extraction, clear any
        // duplicate flag, re-queue extraction, and log a `recapture` event, instead of spawning a
        // brand-new duplicate job. (Electron parity: insertCapture's same-URL update path.)
        let inURL = input.url
        let inCanon = input.canonicalURL
        var urlDescriptor = FetchDescriptor<Capture>(predicate: #Predicate { $0.url == inURL })
        urlDescriptor.fetchLimit = 1
        var existingByURL = try modelContext.fetch(urlDescriptor).first
        if existingByURL == nil, let canon = inCanon, !canon.isEmpty {
            var canonDescriptor = FetchDescriptor<Capture>(predicate: #Predicate { $0.canonicalURL == canon })
            canonDescriptor.fetchLimit = 1
            existingByURL = try modelContext.fetch(canonDescriptor).first
        }
        // Both lookups above are exact string matches, so a recapture of the SAME posting whose URL
        // differs only cosmetically — a trailing slash, a `#fragment`, a `utm_*` tag, reordered query
        // params — missed and forked a duplicate job (Ashby sends an empty canonicalURL, so the
        // fallback couldn't save it either). Compare on the shared normalized form before giving up.
        // O(N) over a few hundred captures, and only on the miss path.
        if existingByURL == nil, let target = URLNormalizer.normalized(inURL) {
            existingByURL = try modelContext.fetch(FetchDescriptor<Capture>()).first { capture in
                if URLNormalizer.normalized(capture.url) == target { return true }
                guard let canon = capture.canonicalURL, !canon.isEmpty else { return false }
                return URLNormalizer.normalized(canon) == target
            }
        }
        if let existing = existingByURL, let job = existing.job {
            existing.url = input.url
            existing.canonicalURL = input.canonicalURL
            existing.pageTitle = input.pageTitle
            existing.selectedText = input.selectedText
            existing.visibleText = input.visibleText
            existing.cleanedDescription = input.cleanedDescription
            existing.structuredDataJSON = input.structuredDataJSON
            if let note = input.userNote, !note.isEmpty { existing.userNote = note }
            existing.rawHash = input.rawHash
            existing.cleanedHash = input.cleanedHash

            job.extractionStatus = .pending
            job.extractionError = nil
            // TASK-517: a same-URL recapture re-queues extraction, so clear the OLD capture's stale
            // extracted fields (override-aware) instead of showing them as current until re-extraction.
            clearExtractionOwnedFields(job)
            job.duplicateOfJobID = nil
            job.duplicateConfidence = nil // TASK-518: confidence is meaningless without the link
            if job.status == .duplicate { job.status = .new }
            // TASK-445: total raw bytes the extension transmitted (selected + visible). The cleaner
            // uses both inputs, so `max` undercounted captures where both contribute. This is the raw
            // capture-pipeline size; deduped unique content is tracked separately as cleanedTextBytes.
            job.rawTextBytes = (input.selectedText?.utf8.count ?? 0) + (input.visibleText?.utf8.count ?? 0)
            job.cleanedTextBytes = input.cleanedDescription?.utf8.count ?? 0
            job.capturedAtDenormalized = existing.capturedAt
            job.updatedAt = Date()

            // Re-queue extraction unless one is already in flight for this job.
            let jid = job.id
            let inflight = try modelContext
                .fetch(FetchDescriptor<LLMRequest>(predicate: #Predicate { $0.finishedAt == nil }))
            let hasActiveExtract = inflight.contains {
                $0.requestType == .extract && $0.job?.id == jid && ($0.status == .queued || $0.status == .running)
            }
            if !hasActiveExtract {
                let req = LLMRequest(requestType: .extract, status: .queued)
                req.job = job
                modelContext.insert(req)
            }

            let event = JobEvent(eventType: "recapture", occurredAt: Date())
            event.job = job
            modelContext.insert(event)

            try modelContext.save()
            return AtomicIngestResult(captureID: existing.id, jobNumber: job.jobNumber ?? 0, isDuplicate: false)
        }

        // Cleaned hash: semantic duplicate — fetch rows matching the hash, filter URL in memory.
        // No fetchLimit: an exact cleaned-hash match set is bounded by genuinely identical postings
        // (usually 0-1), and a fixed cap of 10 silently missed a real duplicate at position 11+ when a
        // boilerplate/templated description collided across many captures.
        var duplicateOfJobID: String?
        if let cHash = input.cleanedHash {
            let url = input.url
            let canonical = input.canonicalURL
            let cleanedDescriptor = FetchDescriptor<Capture>(predicate: #Predicate { $0.cleanedHash == cHash })
            let candidates = try modelContext.fetch(cleanedDescriptor)
            if let dup = candidates.first(where: {
                $0.url != url && ($0.canonicalURL ?? "") != (canonical ?? "")
            }) {
                duplicateOfJobID = dup.job?.id
            }
        }

        // Job number: sort descending, fetch only the top row — O(1) instead of O(N)
        var jobDescriptor = FetchDescriptor<Job>(sortBy: [SortDescriptor(\.jobNumber, order: .reverse)])
        jobDescriptor.fetchLimit = 1
        let maxJobNumber = try modelContext.fetch(jobDescriptor).first?.jobNumber ?? 0
        let jobNumber = maxJobNumber + 1

        // Build the three linked records
        let capture = Capture(
            id: input.captureID,
            url: input.url,
            canonicalURL: input.canonicalURL,
            pageTitle: input.pageTitle,
            selectedText: input.selectedText,
            visibleText: input.visibleText,
            cleanedDescription: input.cleanedDescription,
            structuredDataJSON: input.structuredDataJSON,
            userNote: input.userNote,
            rawHash: input.rawHash,
            cleanedHash: input.cleanedHash
        )
        let job = Job(
            id: input.jobID,
            jobNumber: jobNumber,
            status: duplicateOfJobID != nil ? .duplicate : .new,
            duplicateOfJobID: duplicateOfJobID
        )
        // TASK-445: total raw bytes transmitted (selected + visible), not max — the cleaner uses
        // both inputs, so max undercounted captures where both contribute.
        job.rawTextBytes = (input.selectedText?.utf8.count ?? 0) + (input.visibleText?.utf8.count ?? 0)
        job.cleanedTextBytes = input.cleanedDescription?.utf8.count ?? 0
        job.capturedAtDenormalized = capture.capturedAt
        job.capture = capture

        modelContext.insert(capture)
        modelContext.insert(job)

        // TASK-441: don't auto-queue extraction for a semantic duplicate — it would consume LLM
        // queue slots and provider cost before the user reviews/unmarks it. The user can still
        // re-run extraction explicitly (which clears duplicate status). Unique jobs queue as before.
        if duplicateOfJobID == nil {
            let llmRequest = LLMRequest(requestType: .extract, status: .queued)
            llmRequest.job = job
            modelContext.insert(llmRequest)
        }

        // Timeline: record the capture as a system event so the job has provenance history.
        let captureEvent = JobEvent(eventType: "capture", occurredAt: capture.capturedAt)
        captureEvent.job = job
        modelContext.insert(captureEvent)

        try modelContext.save()

        return AtomicIngestResult(captureID: input.captureID, jobNumber: jobNumber, isDuplicate: false)
    }
}
