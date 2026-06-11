import Foundation
import SwiftData

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

}
