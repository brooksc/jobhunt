import Foundation
import SwiftData

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
    public func markFitScoreFailed(jobID: String, resumeID: String, errorMessage: String?) throws {
        let jobs = try modelContext.fetch(FetchDescriptor<Job>(predicate: #Predicate { $0.id == jobID }))
        guard let job = jobs.first else { return }
        let record = try fitScoreRecord(job: job, resumeID: resumeID)
        record.fitStatus = .failed
        if let msg = errorMessage {
            record.fitScoreJSON = "{\"error\":\"\(msg.replacingOccurrences(of: "\"", with: "\\\""))\"}"
        }
        record.updatedAt = Date()
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
        let allCaptures = try modelContext.fetch(FetchDescriptor<Capture>())

        // Raw hash: exact duplicate — return existing
        if let existing = allCaptures.first(where: { $0.rawHash == input.rawHash }),
           let existingJob = existing.job {
            return AtomicIngestResult(
                captureID: existing.id,
                jobNumber: existingJob.jobNumber ?? 0,
                isDuplicate: true
            )
        }

        // Cleaned hash: semantic duplicate — link but don't block
        var duplicateOfJobID: String?
        if let cHash = input.cleanedHash {
            let url = input.url
            let canonical = input.canonicalURL
            if let dup = allCaptures.first(where: {
                $0.cleanedHash == cHash &&
                    $0.url != url &&
                    ($0.canonicalURL ?? "") != (canonical ?? "")
            }) {
                duplicateOfJobID = dup.job?.id
            }
        }

        // Atomic job number: no suspension between fetch and insert
        let allJobs = try modelContext.fetch(FetchDescriptor<Job>())
        let jobNumber = (allJobs.compactMap(\.jobNumber).max() ?? 0) + 1

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
        let job = Job(id: input.jobID, jobNumber: jobNumber, duplicateOfJobID: duplicateOfJobID)
        job.capture = capture

        let llmRequest = LLMRequest(requestType: .extract, status: .queued)
        llmRequest.job = job

        modelContext.insert(capture)
        modelContext.insert(job)
        modelContext.insert(llmRequest)
        try modelContext.save()

        return AtomicIngestResult(captureID: input.captureID, jobNumber: jobNumber, isDuplicate: false)
    }

}
