import Foundation
import SwiftData

@Model
public final class Contact {
    public var id: String
    public var name: String
    public var role: String?
    public var email: String?
    public var linkedinURL: String?
    public var phone: String?
    public var notes: String?
    public var createdAt: Date
    public var updatedAt: Date

    public var job: Job?

    public init(
        id: String = UUID().uuidString,
        name: String,
        role: String? = nil,
        email: String? = nil,
        linkedinURL: String? = nil,
        phone: String? = nil,
        notes: String? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.role = role
        self.email = email
        self.linkedinURL = linkedinURL
        self.phone = phone
        self.notes = notes
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
