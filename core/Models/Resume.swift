import CryptoKit
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
        fitScores = []
    }
}

public enum ResumeFingerprint {
    /// Stable content hash used to tell whether a fit score still reflects the résumé's current text.
    /// Whitespace-normalised so a reflow or trailing newline isn't mistaken for a substantive edit.
    public static func hash(_ text: String) -> String {
        let normalized = text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        let digest = SHA256.hash(data: Data(normalized.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
