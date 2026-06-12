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

    public func updateResume(id: String, name: String, text: String) async throws {
        let existing = try await store.fetch(FetchDescriptor<Resume>(predicate: #Predicate { $0.id == id }))
        let textChanged = existing.first.map { $0.text != text } ?? false

        try await store.updateOne(Resume.self, predicate: #Predicate { $0.id == id }, id: id) { r in
            r.name = name
            r.text = text
            r.charCount = text.count
            r.updatedAt = Date()
        }

        if textChanged {
            try await store.deleteFitScores(forResumeID: id)
        }
    }

    // MARK: - Delete

    /// Delete a resume by ID. If it was active, promotes the next resume and recomputes job fit mirrors.
    public func deleteResume(id: String) async throws {
        let all = try await store.fetch(FetchDescriptor<Resume>(sortBy: [SortDescriptor(\.sortOrder)]))
        guard let target = all.first(where: { $0.id == id }) else { return }
        let wasActive = target.active
        try await store.deleteOne(Resume.self, predicate: #Predicate { $0.id == id }, id: id)
        var promotedID: String? = nil
        if wasActive {
            let remaining = all.filter { $0.id != id }
            if let nextID = (remaining.first(where: { !$0.active }) ?? remaining.first)?.id {
                try await store.update(Resume.self, predicate: #Predicate { $0.id == nextID }) { $0.active = true }
                promotedID = nextID
            }
        }
        if wasActive {
            try await store.recomputeJobFitMirrors(activeResumeID: promotedID)
        }
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
}
