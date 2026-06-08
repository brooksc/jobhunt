import Foundation
import SwiftData

@Model
public final class JobEvent {
    public var id: String
    public var eventType: String
    public var note: String?
    public var occurredAt: Date
    public var createdAt: Date

    public var job: Job?

    public init(
        id: String = UUID().uuidString,
        eventType: String,
        note: String? = nil,
        occurredAt: Date = Date(),
        createdAt: Date = Date()
    ) {
        self.id = id
        self.eventType = eventType
        self.note = note
        self.occurredAt = occurredAt
        self.createdAt = createdAt
    }
}
