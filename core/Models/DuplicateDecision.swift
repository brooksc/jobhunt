import Foundation
import SwiftData

@Model
public final class DuplicateDecision {
    // Safe to mark unique on fresh installs. For existing stores with duplicate cleanedHash rows,
    // deduplicate before opening the store with this constraint active.
    @Attribute(.unique) public var cleanedHash: String
    public var decision: String
    public var keepJobID: String?
    public var note: String?
    public var decidedAt: Date
    public var createdAt: Date

    public init(
        cleanedHash: String,
        decision: String,
        keepJobID: String? = nil,
        note: String? = nil,
        decidedAt: Date = Date(),
        createdAt: Date = Date()
    ) {
        self.cleanedHash = cleanedHash
        self.decision = decision
        self.keepJobID = keepJobID
        self.note = note
        self.decidedAt = decidedAt
        self.createdAt = createdAt
    }
}
