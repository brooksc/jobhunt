import Foundation
import JobhuntCore

enum JobsSortKey: String, CaseIterable {
    case jobNumber
    case company
    case title
    case status
    case fitScore
    case rating
    case salaryMin
    case salaryMax
    case location
    case capturedAt
    case extractedAt
    case lastOpenedAt
}

struct JobsFilterState: Equatable, Hashable {
    var statusFilter: Set<JobStatus>? // nil = all
    var remoteFilter: Set<RemoteType>? // nil = all
    var searchText: String = ""
    var sortKey: JobsSortKey = .capturedAt
    var sortAscending: Bool = false
    var minFitScore: Int?
    var minRating: Int?
    var minSalary: Int?
    var recentDays: Int?
    /// Session-only filter (not persisted to SavedSearch): extraction outcome.
    var extractionFilter: ExtractionStatus?
    /// TASK-464: session-only filter — show only jobs that passed the location/remote criteria.
    var meetsCriteriaOnly: Bool = false
    /// TASK-630: show only applied-funnel jobs that still need referral outreach.
    var needsReferralOutreach: Bool = false

    var hasActiveFilters: Bool {
        statusFilter != nil || remoteFilter != nil || !searchText.isEmpty
            || minFitScore != nil || minRating != nil || minSalary != nil || recentDays != nil
            || extractionFilter != nil || meetsCriteriaOnly || needsReferralOutreach
    }

    var activeFilterCount: Int {
        [
            statusFilter != nil,
            remoteFilter != nil,
            !searchText.isEmpty,
            minFitScore != nil,
            minRating != nil,
            minSalary != nil,
            recentDays != nil,
            extractionFilter != nil,
            meetsCriteriaOnly,
            needsReferralOutreach
        ]
        .count(where: { $0 })
    }

    // MARK: SavedSearch interop

    init() {}

    init(from search: SavedSearch) {
        if !search.statusFilterRaw.isEmpty {
            statusFilter = Set(search.statusFilterRaw.compactMap { JobStatus(rawValue: $0) })
        }
        if !search.remoteFilterRaw.isEmpty {
            remoteFilter = Set(search.remoteFilterRaw.compactMap { RemoteType(rawValue: $0) })
        }
        searchText = search.searchText
        sortKey = JobsSortKey(rawValue: search.sortKeyRaw) ?? .capturedAt
        sortAscending = search.sortAscending
        minFitScore = search.minFitScore
        minRating = search.minRating
        minSalary = search.minSalary
        recentDays = search.recentDays
    }

    func toSavedSearch(name: String, sortOrder: Int = 0) -> SavedSearch {
        SavedSearch(
            name: name,
            sortOrder: sortOrder,
            statusFilterRaw: statusFilter?.map(\.rawValue) ?? [],
            remoteFilterRaw: remoteFilter?.map(\.rawValue) ?? [],
            searchText: searchText,
            minFitScore: minFitScore,
            minRating: minRating,
            minSalary: minSalary,
            recentDays: recentDays,
            sortKeyRaw: sortKey.rawValue,
            sortAscending: sortAscending
        )
    }
}
