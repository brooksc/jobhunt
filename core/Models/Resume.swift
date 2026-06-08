import Foundation
import SwiftData

@Model
public final class Resume {
    public var id: String
    public var name: String
    public var filename: String?
    public var text: String
    public var charCount: Int
    public var active: Bool
    public var sortOrder: Int
    public var createdAt: Date
    public var updatedAt: Date

    @Relationship(deleteRule: .cascade, inverse: \JobFitScore.resume)
    public var fitScores: [JobFitScore]

    public init(
        id: String = UUID().uuidString,
        name: String,
        filename: String? = nil,
        text: String = "",
        charCount: Int = 0,
        active: Bool = true,
        sortOrder: Int = 0,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.filename = filename
        self.text = text
        self.charCount = charCount
        self.active = active
        self.sortOrder = sortOrder
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.fitScores = []
    }
}
