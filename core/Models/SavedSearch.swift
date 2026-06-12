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
        if !statusFilterRaw.isEmpty, !statusFilterRaw.contains(job.status.rawValue) { return false }
        if !remoteFilterRaw.isEmpty {
            guard let rt = job.remoteType, remoteFilterRaw.contains(rt.rawValue) else { return false }
        }
        if let min = minFitScore, (job.fitScore ?? 0) < min { return false }
        if let min = minRating, (job.rating ?? 0) < min { return false }
        if let min = minSalary {
            let salary = job.salaryMin ?? job.salaryMax ?? 0
            if salary < min { return false }
        }
        if let days = recentDays {
            let cutoff = Calendar.current.date(byAdding: .day, value: -days, to: Date()) ?? Date()
            if (job.capturedAtDenormalized ?? job.createdAt) < cutoff { return false }
        }
        if !searchText.isEmpty {
            let q = searchText.lowercased().trimmingCharacters(in: .whitespaces)
            let matchNum = q.hasPrefix("#") ? String(q.dropFirst()) : q
            let textFields = [job.company, job.title, job.location].compactMap { $0 }.joined(separator: " ").lowercased()
            let textMatch = textFields.contains(q)
            let numMatch = job.jobNumber.map { String($0).contains(matchNum) } ?? false
            if !textMatch && !numMatch { return false }
        }
        return true
    }
}
