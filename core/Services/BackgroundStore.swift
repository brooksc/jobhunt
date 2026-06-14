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

        if resume?.active == true {
            job.fitScore = overall
            job.fitStatus = .succeeded
            job.fitScoreJSON = fitJSON
            job.updatedAt = Date()
        }

        try modelContext.save()
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
            // After deletion, set denormalized fields from the active-resume score if any remain.
            let activeScore = job.fitScores.first { $0.resume?.active == true }
            job.fitScore = activeScore?.fitScore
            job.fitStatus = activeScore?.fitStatus ?? .none
            job.fitScoreJSON = activeScore?.fitScoreJSON
            job.updatedAt = Date()
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
            record.fitScoreJSON = "{\"error\":\"\(msg.replacingOccurrences(of: "\"", with: "\\\""))\"}"
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

    /// Recompute Job.fitScore/fitStatus/fitScoreJSON mirrors for all jobs.
    /// Sets each job's mirror from the active-resume's JobFitScore if one exists,
    /// or resets to .none/nil if the new active resume has no score for that job.
    /// Pass nil activeResumeID when no resume remains active.
    public func recomputeJobFitMirrors(activeResumeID: String?) throws {
        let jobs = try modelContext.fetch(FetchDescriptor<Job>())
        for job in jobs {
            let activeScore: JobFitScore?
            if let rid = activeResumeID {
                activeScore = job.fitScores.first { $0.resume?.id == rid }
            } else {
                activeScore = nil
            }
            job.fitScore = activeScore?.fitScore
            job.fitStatus = activeScore?.fitStatus ?? .none
            job.fitScoreJSON = activeScore?.fitScoreJSON
            job.updatedAt = Date()
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

        let llmRequest = LLMRequest(requestType: .extract, status: .queued)
        llmRequest.job = job

        modelContext.insert(capture)
        modelContext.insert(job)
        modelContext.insert(llmRequest)

        // Timeline: record the capture as a system event so the job has provenance history.
        let captureEvent = JobEvent(eventType: "capture", occurredAt: capture.capturedAt)
        captureEvent.job = job
        modelContext.insert(captureEvent)

        try modelContext.save()

        return AtomicIngestResult(captureID: input.captureID, jobNumber: jobNumber, isDuplicate: false)
    }

}
