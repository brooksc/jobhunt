import Foundation

/// The canonical identity strings for the Jobs search-bar tokens (the blue chips). This is the single
/// source of truth shared by the app's `JobSearchToken.id` and `SavedSearch.expectedTokenIDs` so the
/// two can't drift — the Jobs view uses that equality to tell a programmatic saved-search apply (keep
/// the saved search active) from a user token edit (clear it). See TASK-572.
public enum SearchTokenID {
    public static func status(_ raw: String) -> String {
        "status:\(raw)"
    }

    public static func remote(_ raw: String) -> String {
        "remote:\(raw)"
    }

    public static func fitScore(_ n: Int) -> String {
        "fitScore:\(n)"
    }

    public static func salary(_ n: Int) -> String {
        "salary:\(n)"
    }

    public static func rating(_ n: Int) -> String {
        "rating:\(n)"
    }

    public static func recentDays(_ d: Int) -> String {
        "recent:\(d)"
    }
}

public extension SavedSearch {
    /// The token identifiers this saved search maps to in the Jobs search bar. The Jobs view installs
    /// exactly these tokens when the search is selected; the token-change observer keeps the search
    /// active while the current tokens match this set, and clears it on any user edit (TASK-572).
    var expectedTokenIDs: Set<String> {
        var ids: Set<String> = []
        for raw in statusFilterRaw {
            ids.insert(SearchTokenID.status(raw))
        }
        for raw in remoteFilterRaw {
            ids.insert(SearchTokenID.remote(raw))
        }
        if let minFitScore { ids.insert(SearchTokenID.fitScore(minFitScore)) }
        if let minSalary { ids.insert(SearchTokenID.salary(minSalary)) }
        if let minRating { ids.insert(SearchTokenID.rating(minRating)) }
        if let recentDays { ids.insert(SearchTokenID.recentDays(recentDays)) }
        return ids
    }
}
