import Foundation
import SwiftData

@Model
public final class Capture {
    public var id: String
    public var url: String
    public var canonicalURL: String?
    public var pageTitle: String
    public var selectedText: String?
    public var visibleText: String?
    public var cleanedDescription: String?
    public var structuredDataJSON: String?
    public var userNote: String?
    /// Which `JobSource` discovered this, when automatic search created it. Nil for a browser
    /// capture, a paste or MCP.
    ///
    /// Structured rather than inferred from `userNote`. The note is user-facing copy the user can
    /// edit and a future release may localise, so counting discoveries by its prefix would lose
    /// real finds silently and miscount any other note that happened to start the same way.
    public var discoveredBySourceID: String?
    // Safe to mark unique on fresh installs. For existing stores with duplicate rawHash rows,
    // deduplicate before opening the store with this constraint active.
    @Attribute(.unique) public var rawHash: String
    public var cleanedHash: String?
    public var capturedAt: Date
    public var createdAt: Date

    @Relationship(deleteRule: .nullify, inverse: \Job.capture)
    public var job: Job?

    public init(
        id: String = UUID().uuidString,
        url: String,
        canonicalURL: String? = nil,
        pageTitle: String,
        selectedText: String? = nil,
        visibleText: String? = nil,
        cleanedDescription: String? = nil,
        structuredDataJSON: String? = nil,
        userNote: String? = nil,
        discoveredBySourceID: String? = nil,
        rawHash: String,
        cleanedHash: String? = nil,
        capturedAt: Date = Date(),
        createdAt: Date = Date()
    ) {
        self.id = id
        self.url = url
        self.canonicalURL = canonicalURL
        self.pageTitle = pageTitle
        self.selectedText = selectedText
        self.visibleText = visibleText
        self.cleanedDescription = cleanedDescription
        self.structuredDataJSON = structuredDataJSON
        self.userNote = userNote
        self.discoveredBySourceID = discoveredBySourceID
        self.rawHash = rawHash
        self.cleanedHash = cleanedHash
        self.capturedAt = capturedAt
        self.createdAt = createdAt
    }
}
