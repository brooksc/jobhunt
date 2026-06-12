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
    /// Call this instead of a bare `update(Job.self...)` after fit scoring so the FitTab has data.
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

        job.fitScore = overall
        job.fitStatus = .succeeded
        job.fitScoreJSON = fitJSON
        job.updatedAt = Date()

        let existing = job.fitScores.first { $0.resume?.id == resumeID }
        let record: JobFitScore
        if let existing {
            record = existing
        } else {
            record = JobFitScore()
            modelContext.insert(record)
            record.job = job
            let resumes = try modelContext.fetch(FetchDescriptor<Resume>(predicate: #Predicate { $0.id == resumeID }))
            record.resume = resumes.first
        }
        record.fitScore = overall
        record.fitStatus = .succeeded
        record.fitScoreJSON = fitJSON
        record.model = model
        record.scoredAt = scoredAt
        record.updatedAt = Date()

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
            if job.fitScores.isEmpty {
                job.fitScore = nil
                job.fitStatus = .none
                job.fitScoreJSON = nil
            } else if let best = job.fitScores.max(by: { ($0.fitScore ?? 0) < ($1.fitScore ?? 0) }) {
                job.fitScore = best.fitScore
                job.fitStatus = best.fitStatus
                job.fitScoreJSON = best.fitScoreJSON
            }
            job.updatedAt = Date()
        }
        try modelContext.save()
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
