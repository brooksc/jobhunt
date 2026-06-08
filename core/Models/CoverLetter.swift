import Foundation
import SwiftData

@Model
public final class CoverLetter {
    public var id: String
    public var content: String
    public var instructions: String?
    public var model: String?
    public var createdAt: Date

    public var job: Job?

    public init(
        id: String = UUID().uuidString,
        content: String,
        instructions: String? = nil,
        model: String? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.content = content
        self.instructions = instructions
        self.model = model
        self.createdAt = createdAt
    }
}
