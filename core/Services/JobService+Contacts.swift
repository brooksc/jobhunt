import Foundation
import SwiftData

// MARK: - Contacts and cover letters

/// Split out of `JobService` for size only: the actor sits at SwiftLint's 500-line limit and the
/// create-only ingestion work pushed it over. These are self-contained CRUD wrappers with no
/// relationship to ingestion, so they were the cheapest thing to move.
public extension JobService {
    func createContact(jobID: String, name: String, email: String?, role: String?) async throws {
        // TASK-526: created + linked inside the store actor.
        try await store.insertContact(jobID: jobID, name: name, role: role, email: email)
    }

    func updateContact(contactID: String, name: String, email: String?, role: String?) async throws {
        let id = contactID
        try await store.update(Contact.self, predicate: #Predicate { $0.id == id }) { contact in
            contact.name = name
            contact.email = email
            contact.role = role
            contact.updatedAt = Date()
        }
    }

    func deleteContact(contactID: String) async throws {
        let id = contactID
        try await store.delete(Contact.self, predicate: #Predicate { $0.id == id })
    }

    // MARK: - Cover letters

    func deleteCoverLetter(id: String) async throws {
        let covID = id
        try await store.delete(CoverLetter.self, predicate: #Predicate { $0.id == covID })
    }
}
