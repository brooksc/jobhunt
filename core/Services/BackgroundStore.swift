// Large cohesive file; splitting deferred (TASK-545).
// swiftlint:disable file_length type_body_length function_body_length
import Foundation
import SwiftData

// MARK: - BackgroundStore errors

public enum BackgroundStoreError: Error, LocalizedError, Sendable {
    case notFound(String)
    case multipleMatches(count: Int)
    public var errorDescription: String? {
        switch self {
        case let .notFound(id): return "Record not found: \(id)"
        case let .multipleMatches(count): return "Expected exactly one match but found \(count)"
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
        let jobsByID = Dictionary(uniqueKeysWithValues: allJobs.map { ($0.id, $0) })
        for id in uniqueIDs where jobsByID[id] == nil {
            throw BackgroundStoreError.notFound(id)
        }

        for id in uniqueIDs {
            guard let job = jobsByID[id] else { continue }
            let oldStatus = job.status
            job.status = status
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
        _ = resume // resume captured for the record relationship above

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

    /// Pure computation of a job's denormalized fit mirror from the best-scoring resume across ALL
    /// its fit-score records (Electron parity: jobs.fit_score = MAX across resumes). Falls back to
    /// running/pending/failed/none when no resume has a numeric score yet. No mutation/side effects.
    private func computedFitMirror(for job: Job) -> (score: Int?, status: FitStatus, json: String?) {
        // Only resume-linked scores count toward the mirror — an orphaned score (no resume) is a
        // legacy/unmigrated artifact and must not drive the headline number.
        let scored = job.fitScores.filter { $0.fitScore != nil && $0.resume != nil }
        if let best = scored.max(by: { ($0.fitScore ?? 0) < ($1.fitScore ?? 0) }) {
            return (best.fitScore, .succeeded, best.fitScoreJSON)
        } else if job.fitScores.contains(where: { $0.fitStatus == .running }) {
            return (nil, .running, nil)
        } else if job.fitScores.contains(where: { $0.fitStatus == .pending }) {
            return (nil, .pending, nil)
        } else if job.fitScores.contains(where: { $0.fitStatus == .failed }) {
            return (nil, .failed, nil)
        } else {
            return (nil, FitStatus.none, nil)
        }
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
        let allScores = try modelContext.fetch(FetchDescriptor<JobFitScore>())
        var updated = 0
        var affectedJobIDs = Set<String>()
        for record in allScores {
            guard record.fitStatus == .succeeded,
                  let json = record.fitScoreJSON,
                  let result = FitScorer.rescoreFromJSON(json) else { continue }
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

    /// Delete all JobFitScore records for a resume and reset denormalized fit fields on affected jobs.
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
        if !overrides.contains("seniority") { job.seniority = result.seniority }
        if !overrides.contains("applicationURL") { job.applicationURL = result.applicationURL }
        job.extractionConfidence = result.extractionConfidence
        job.meetsCriteria = result.meetsCriteria
        job.extractionModel = result.extractionModel
        job.extractionStatus = .succeeded
        job.extractionError = nil
        job.extractedAt = metadata.finishedAt
        job.unread = true
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
            error: error, promptChars: promptChars, responseChars: responseChars,
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

    /// Run domain-duplicate detection across all jobs and persist results: flag each detected
    /// candidate with duplicateOfJobID + confidence + `.duplicate` status, and log a
    /// `duplicate_detected` event. Skips pairs already resolved via DuplicateDecision.
    /// (Electron parity: detectDomainDuplicateJobs after markExtractionSucceeded.) Returns count flagged.
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

        // Cleaned hash: semantic duplicate — fetch only rows matching the hash, filter URL in memory
        // (typically 0-1 rows match, so full scan never materialises)
        var duplicateOfJobID: String?
        if let cHash = input.cleanedHash {
            let url = input.url
            let canonical = input.canonicalURL
            var cleanedDescriptor = FetchDescriptor<Capture>(predicate: #Predicate { $0.cleanedHash == cHash })
            cleanedDescriptor.fetchLimit = 10
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
