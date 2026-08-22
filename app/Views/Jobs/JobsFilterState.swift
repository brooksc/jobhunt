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
    /// Session-only filter (not persisted to SavedSearch) on the location/remote criteria verdict:
    /// nil = any (TASK-464, bucketed in TASK-649). "Not stated" is split out from "doesn't meet"
    /// because `LocationCriteria` scores a silent posting as onsite — so without the split, postings
    /// that simply never mention an arrangement read as confirmed rejections.
    var criteriaBucket: JobFilterRules.CriteriaBucket?
    /// Session-only data-quality filter (TASK-649 follow-up): nil = any job. Evaluating quality
    /// faults each job's Capture when the byte caches are missing, so the predicate skips the work
    /// entirely while this is nil.
    var qualityFilter: JobFilterRules.QualityFilter?
    /// Session-only source filter: capture hosts to include (nil = any). Not persisted to
    /// SavedSearch, like the other triage filters.
    var sourceHosts: Set<String>?
    /// Session-only: only jobs never opened, for "what haven't I looked at" triage.
    var unreadOnly: Bool = false
    /// Session-only: only jobs that were never fit-scored. Kept separate from `minFitScore` (which IS
    /// persisted to SavedSearch) so saved searches keep working unchanged.
    var unscoredOnly: Bool = false
    /// TASK-630: show only applied-funnel jobs that still need referral outreach.
    var needsReferralOutreach: Bool = false

    var hasActiveFilters: Bool {
        statusFilter != nil || remoteFilter != nil || !searchText.isEmpty
            || minFitScore != nil || minRating != nil || minSalary != nil || recentDays != nil
            || extractionFilter != nil || criteriaBucket != nil || qualityFilter != nil
            || sourceHosts != nil || unreadOnly || unscoredOnly || needsReferralOutreach
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
            criteriaBucket != nil,
            qualityFilter != nil,
            sourceHosts != nil,
            unreadOnly,
            unscoredOnly,
            needsReferralOutreach
        ]
        .count(where: { $0 })
    }

    // MARK: SavedSearch interop

    init() {}

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
