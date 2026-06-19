import Foundation

// MARK: - JobMatchFields (TASK-364)

/// Sendable, Hashable snapshot of exactly the `Job` fields a saved-search filter consults. Because
/// this is the single definition of "fields that matter to matching", a change signal built from
/// these snapshots can't drift out of sync with the match logic, and the match work can run off the
/// main actor (Job is a main-actor-bound `@Model`).
public struct JobMatchFields: Sendable, Hashable {
    public let statusRaw: String
    public let remoteTypeRaw: String?
    public let fitScore: Int?
    public let rating: Int?
    public let salaryMin: Int?
    public let salaryMax: Int?
    public let capturedAt: Date
    public let company: String?
    public let title: String?
    public let location: String?
    public let jobNumber: Int?

    public init(job: Job) {
        statusRaw = job.status.rawValue
        remoteTypeRaw = job.remoteType?.rawValue
        fitScore = job.fitScore
        rating = job.rating
        salaryMin = job.salaryMin
        salaryMax = job.salaryMax
        capturedAt = job.capturedAtDenormalized ?? job.createdAt
        company = job.company
        title = job.title
        location = job.location
        jobNumber = job.jobNumber
    }
}

// MARK: - SavedSearchCriteria

/// Sendable, Hashable value capturing a `SavedSearch`'s filter predicate, decoupled from the
/// SwiftData model so matching can run off the main actor and be unit-tested in isolation.
public struct SavedSearchCriteria: Sendable, Hashable {
    public let statusFilterRaw: [String]
    public let remoteFilterRaw: [String]
    public let searchText: String
    public let minFitScore: Int?
    public let minRating: Int?
    public let minSalary: Int?
    public let recentDays: Int?

    public init(_ search: SavedSearch) {
        statusFilterRaw = search.statusFilterRaw
        remoteFilterRaw = search.remoteFilterRaw
        searchText = search.searchText
        minFitScore = search.minFitScore
        minRating = search.minRating
        minSalary = search.minSalary
        recentDays = search.recentDays
    }

    /// Whether a job (snapshot) passes this search's filters. `now` is injected so `recentDays`
    /// cutoffs are deterministic in tests.
    public func matches(_ f: JobMatchFields, now: Date) -> Bool {
        if !statusFilterRaw.isEmpty, !statusFilterRaw.contains(f.statusRaw) { return false }
        if !remoteFilterRaw.isEmpty {
            guard let rt = f.remoteTypeRaw, remoteFilterRaw.contains(rt) else { return false }
        }
        if let min = minFitScore, (f.fitScore ?? 0) < min { return false }
        if let min = minRating, (f.rating ?? 0) < min { return false }
        if let min = minSalary {
            let salary = f.salaryMin ?? f.salaryMax ?? 0
            if salary < min { return false }
        }
        if let days = recentDays {
            let cutoff = Calendar.current.date(byAdding: .day, value: -days, to: now) ?? now
            if f.capturedAt < cutoff { return false }
        }
        if !searchText.isEmpty {
            let q = searchText.lowercased().trimmingCharacters(in: .whitespaces)
            let matchNum = q.hasPrefix("#") ? String(q.dropFirst()) : q
            let textFields = [f.company, f.title, f.location].compactMap(\.self).joined(separator: " ").lowercased()
            let textMatch = textFields.contains(q)
            let numMatch = f.jobNumber.map { String($0).contains(matchNum) } ?? false
            if !textMatch && !numMatch { return false }
        }
        return true
    }
}
