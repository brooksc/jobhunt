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

// MARK: - BackgroundStore

/// All background writes (extraction, availability, bulk ops, demo seeding) funnel through here.
/// UI @Query views update automatically via SwiftData change tracking — no manual broadcast needed.
@ModelActor
public actor BackgroundStore {
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
        for orphan in orphans { modelContext.delete(orphan) }
        for job in affected { recomputeJobFitSummary(job) }
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

    /// Delete a single known model object, then save.
    public func deleteObject(_ model: some PersistentModel) throws {
        modelContext.delete(model)
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
    public func fetch<T: PersistentModel>(_ descriptor: FetchDescriptor<T>) throws -> [T] {
        try modelContext.fetch(descriptor)
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
        let jobs = try modelContext.fetch(FetchDescriptor<Job>(predicate: #Predicate { $0.id == jobID }))
        guard let job = jobs.first else { return }

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
        _ = resume  // resume captured for the record relationship above

        // Job-level mirror reflects the BEST score across all resumes (Electron parity).
        recomputeJobFitSummary(job)

        try modelContext.save()
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
        for orphan in orphans { modelContext.delete(orphan) }
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
    public func deleteFitScores(forResumeID resumeID: String) throws {
        let allScores = try modelContext.fetch(FetchDescriptor<JobFitScore>())
        let toDelete = allScores.filter { $0.resume?.id == resumeID }
        guard !toDelete.isEmpty else { return }

        let affectedJobs = toDelete.compactMap(\.job)
        for score in toDelete { modelContext.delete(score) }
        try modelContext.save()

        for job in affectedJobs {
            recomputeJobFitSummary(job)
        }
        try modelContext.save()
    }

    /// Create or update a JobFitScore record with fitStatus = .pending.
    public func markFitScorePending(jobID: String, resumeID: String) throws {
        let jobs = try modelContext.fetch(FetchDescriptor<Job>(predicate: #Predicate { $0.id == jobID }))
        guard let job = jobs.first else { return }
        let record = try fitScoreRecord(job: job, resumeID: resumeID)
        record.fitStatus = .pending
        record.updatedAt = Date()
        try modelContext.save()
    }

    /// Create or update a JobFitScore record with fitStatus = .running.
    public func markFitScoreRunning(jobID: String, resumeID: String) throws {
        let jobs = try modelContext.fetch(FetchDescriptor<Job>(predicate: #Predicate { $0.id == jobID }))
        guard let job = jobs.first else { return }
        let record = try fitScoreRecord(job: job, resumeID: resumeID)
        record.fitStatus = .running
        record.updatedAt = Date()
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
    public func insertFitBatch(jobs: [Job], resume: Resume) throws {
        for job in jobs {
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
            record.updatedAt = Date()
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
        let activeResumes = try modelContext.fetch(FetchDescriptor<Resume>(predicate: #Predicate { $0.active == true }))
        guard !activeResumes.isEmpty else { return 0 }

        // Resume IDs that already have an in-flight fit request for this job (avoid duplicates).
        let inflight = try modelContext.fetch(FetchDescriptor<LLMRequest>(predicate: #Predicate { $0.finishedAt == nil }))
        let busyResumeIDs = Set(
            inflight
                .filter { $0.requestType == .fit && $0.job?.id == jid && ($0.status == .queued || $0.status == .running) }
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
            record.updatedAt = Date()
            queued += 1
        }
        if queued > 0 { try modelContext.save() }
        return queued
    }

    /// Append a timeline event to a job.
    public func insertJobEvent(jobID: String, eventType: String, note: String? = nil, occurredAt: Date = Date()) throws {
        let jid = jobID
        let jobs = try modelContext.fetch(FetchDescriptor<Job>(predicate: #Predicate { $0.id == jid }))
        guard let job = jobs.first else { return }
        let event = JobEvent(eventType: eventType, note: note, occurredAt: occurredAt)
        event.job = job
        modelContext.insert(event)
        try modelContext.save()
    }

    /// Recompute every job's fit mirror from the best-scoring resume across resumes.
    /// `activeResumeID` is retained for source compatibility but no longer affects the mirror
    /// (the mirror is best-across-resumes, not active-resume-specific).
    public func recomputeJobFitMirrors(activeResumeID _: String?) throws {
        let jobs = try modelContext.fetch(FetchDescriptor<Job>())
        for job in jobs { recomputeJobFitSummary(job) }
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
            if candidate.duplicateOfJobID == pair.original.id { continue }  // already flagged
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

    /// Record (or update) a duplicate decision so a resolved pair does not resurface in detection.
    public func upsertDuplicateDecision(cleanedHash: String, decision: String, keepJobID: String?) throws {
        let ch = cleanedHash
        let existing = try modelContext.fetch(FetchDescriptor<DuplicateDecision>(predicate: #Predicate { $0.cleanedHash == ch }))
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
            job.duplicateOfJobID = nil
            if job.status == .duplicate { job.status = .new }
            job.rawTextBytes = max(input.selectedText?.utf8.count ?? 0, input.visibleText?.utf8.count ?? 0)
            job.cleanedTextBytes = input.cleanedDescription?.utf8.count ?? 0
            job.capturedAtDenormalized = existing.capturedAt
            job.updatedAt = Date()

            // Re-queue extraction unless one is already in flight for this job.
            let jid = job.id
            let inflight = try modelContext.fetch(FetchDescriptor<LLMRequest>(predicate: #Predicate { $0.finishedAt == nil }))
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
        job.rawTextBytes = max(
            input.selectedText?.utf8.count ?? 0,
            input.visibleText?.utf8.count ?? 0
        )
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
