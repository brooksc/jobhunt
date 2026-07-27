import Foundation
import SwiftData

public enum ResumeServiceError: Error, LocalizedError, Sendable {
    case resumeNotFound(String)

    public var errorDescription: String? {
        switch self {
        case let .resumeNotFound(id): "Resume not found: \(id)"
        }
    }
}

/// Service layer for resume CRUD and activation.
/// Views should use this instead of mutating Resume objects via modelContext directly.
public actor ResumeService {
    private let store: BackgroundStore

    public init(store: BackgroundStore) {
        self.store = store
    }

    // MARK: - Create

    public func addResume(name: String, text: String) async throws {
        let all = try await store.fetch(FetchDescriptor<Resume>(sortBy: [SortDescriptor(\.sortOrder)]))
        let resume = Resume(
            name: name,
            text: text,
            charCount: text.count,
            active: all.isEmpty,
            sortOrder: all.count
        )
        try await store.insert(resume)
    }

    // MARK: - Update

    /// Returns the number of fit scores cleared because the résumé text changed (0 if only the name
    /// changed). Editing the text invalidates this résumé's scores, so the caller can tell the user.
    @discardableResult
    public func updateResume(id: String, name: String, text: String) async throws -> Int {
        let existing = try await store.fetch(FetchDescriptor<Resume>(predicate: #Predicate { $0.id == id }))
        let textChanged = existing.first.map { $0.text != text } ?? false

        try await store.updateOne(Resume.self, predicate: #Predicate { $0.id == id }, id: id) { r in
            r.name = name
            r.text = text
            r.charCount = text.count
            r.updatedAt = Date()
        }

        // Editing a résumé no longer deletes its fit scores. Those scores are still real work — they
        // simply describe the PREVIOUS text, so they're marked stale for display and the caller decides
        // whether to spend money re-scoring. Returns how many jobs a re-score would cover.
        guard textChanged else { return 0 }
        return try await store.staleFitJobIDs(forResumeID: id).count
    }

    // MARK: - Delete

    /// Delete a resume by ID. Its fit scores cascade-delete; job mirrors recompute from what
    /// remains. Keeps at least one resume active when any remain (so auto-scoring still fires).
    public func deleteResume(id: String) async throws {
        let all = try await store.fetch(FetchDescriptor<Resume>(sortBy: [SortDescriptor(\.sortOrder)]))
        guard all.contains(where: { $0.id == id }) else { return }
        try await store.deleteOne(Resume.self, predicate: #Predicate { $0.id == id }, id: id)

        let remaining = all.filter { $0.id != id }
        if !remaining.isEmpty, !remaining.contains(where: \.active) {
            let nextID = remaining[0].id
            try await store.update(Resume.self, predicate: #Predicate { $0.id == nextID }) { $0.active = true }
        }
        // Best-across-resumes mirror recompute (argument retained for signature compatibility).
        try await store.recomputeJobFitMirrors(activeResumeID: nil)
    }

    // MARK: - Activation

    /// Set a resume as the sole active resume; deactivates all others.
    /// Throws `ResumeServiceError.resumeNotFound` if the ID doesn't exist,
    /// leaving the current active resume unchanged.
    public func setActiveResume(id: String) async throws {
        let targets = try await store.fetch(FetchDescriptor<Resume>(predicate: #Predicate { $0.id == id }))
        guard targets.first != nil else {
            throw ResumeServiceError.resumeNotFound(id)
        }
        try await store.update(Resume.self, predicate: nil) { r in r.active = false }
        try await store.updateOne(Resume.self, predicate: #Predicate { $0.id == id }, id: id) { r in
            r.active = true
            r.updatedAt = Date()
        }
        try await store.recomputeJobFitMirrors(activeResumeID: id)
    }

    /// Toggle a single resume's active flag without affecting the others. Multiple resumes may
    /// be active; every active resume is auto-scored against newly-extracted jobs.
    public func setResumeActive(id: String, active: Bool) async throws {
        let targets = try await store.fetch(FetchDescriptor<Resume>(predicate: #Predicate { $0.id == id }))
        guard targets.first != nil else {
            throw ResumeServiceError.resumeNotFound(id)
        }
        try await store.updateOne(Resume.self, predicate: #Predicate { $0.id == id }, id: id) { r in
            r.active = active
            r.updatedAt = Date()
        }
    }
}
