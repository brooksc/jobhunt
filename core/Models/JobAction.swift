import Foundation
import SwiftData

@Model
public final class JobAction {
    public var id: String
    public var note: String
    public var dueDate: Date
    public var completedAt: Date?
    public var snoozedUntil: Date?
    public var createdAt: Date
    public var updatedAt: Date

    public var job: Job?

    public init(
        id: String = UUID().uuidString,
        note: String = "",
        dueDate: Date,
        completedAt: Date? = nil,
        snoozedUntil: Date? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.note = note
        self.dueDate = dueDate
        self.completedAt = completedAt
        self.snoozedUntil = snoozedUntil
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
