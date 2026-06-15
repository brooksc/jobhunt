import Foundation
import SwiftData

@Model
public final class SavedSearch {
    @Attribute(.unique) public var id: String
    public var name: String
    public var sortOrder: Int
    public var createdAt: Date

    // Filter fields — stored as raw strings/values for SwiftData compatibility
    public var statusFilterRaw: [String]  // JobStatus raw values; empty = all
    public var remoteFilterRaw: [String]  // RemoteType raw values; empty = all
    public var searchText: String
    public var minFitScore: Int?
    public var minRating: Int?
    public var minSalary: Int?
    public var recentDays: Int?

    // Sort
    public var sortKeyRaw: String
    public var sortAscending: Bool

    public init(
        name: String,
        sortOrder: Int = 0,
        statusFilterRaw: [String] = [],
        remoteFilterRaw: [String] = [],
        searchText: String = "",
        minFitScore: Int? = nil,
        minRating: Int? = nil,
        minSalary: Int? = nil,
        recentDays: Int? = nil,
        sortKeyRaw: String = "capturedAt",
        sortAscending: Bool = false
    ) {
        self.id = UUID().uuidString
        self.name = name
        self.sortOrder = sortOrder
        self.createdAt = Date()
        self.statusFilterRaw = statusFilterRaw
        self.remoteFilterRaw = remoteFilterRaw
        self.searchText = searchText
        self.minFitScore = minFitScore
        self.minRating = minRating
        self.minSalary = minSalary
        self.recentDays = recentDays
        self.sortKeyRaw = sortKeyRaw
        self.sortAscending = sortAscending
    }

    /// Whether a given Job passes this search's filters.
    public func matches(_ job: Job) -> Bool {
        // Delegates to the Sendable projection (TASK-364) so the filter logic has one definition,
        // usable both here and off the main actor for bounded count computation.
        SavedSearchCriteria(self).matches(JobMatchFields(job: job), now: Date())
    }
}
