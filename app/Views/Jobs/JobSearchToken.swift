import JobhuntCore
import SwiftData
import SwiftUI

/// Structured search tokens that appear as blue chips in the search bar.
enum JobSearchToken: Identifiable, Hashable {
    case status(JobStatus)
    case minFitScore(Int)
    case minSalary(Int)
    case remoteType(RemoteType)
    case minRating(Int)
    case recentDays(Int)

    /// IDs come from the shared core builders so they can't drift from `SavedSearch.expectedTokenIDs`,
    /// which the Jobs view compares against to keep a programmatically-applied saved search active.
    var id: String {
        switch self {
        case let .status(s): SearchTokenID.status(s.rawValue)
        case let .minFitScore(n): SearchTokenID.fitScore(n)
        case let .minSalary(n): SearchTokenID.salary(n)
        case let .remoteType(rt): SearchTokenID.remote(rt.rawValue)
        case let .minRating(n): SearchTokenID.rating(n)
        case let .recentDays(d): SearchTokenID.recentDays(d)
        }
    }

    var label: String {
        switch self {
        case let .status(s): s.displayName
        case let .minFitScore(n): "Fit ≥ \(n)"
        case let .minSalary(n): "Salary ≥ $\(n / 1000)k"
        case let .remoteType(rt): rt.displayName
        case let .minRating(n): "Rating ≥ \(n)★"
        case let .recentDays(d): "Last \(d)d"
        }
    }

    var systemImage: String {
        switch self {
        case .status: "tag"
        case .minFitScore: "chart.bar"
        case .minSalary: "dollarsign"
        case .remoteType: "network"
        case .minRating: "star"
        case .recentDays: "calendar"
        }
    }
}

/// Build search suggestions based on what the user is typing.
struct JobSearchSuggestions: View {
    let searchText: String
    /// Companies and titles the user has actually captured (TASK-591). A @Query rather than a
    /// cached set: it re-runs when a capture lands, so a company added mid-session is suggestable
    /// without any invalidation of our own.
    @Query private var allJobs: [Job]

    var body: some View {
        let q = searchText.lowercased()

        if q.isEmpty { EmptyView() }

        // Status suggestions
        if q.hasPrefix("s") || q.hasPrefix("stat") || q.hasPrefix("applied") || q.hasPrefix("int") {
            ForEach(JobStatus.allCases, id: \.self) { s in
                if s.displayName.lowercased().hasPrefix(q) || q.hasPrefix("stat") {
                    Label(s.displayName, systemImage: "tag")
                        .searchCompletion(JobSearchToken.status(s))
                }
            }
        }

        // Remote suggestions
        if q.hasPrefix("r") || q.hasPrefix("rem") || q.hasPrefix("hyb") || q.hasPrefix("on") {
            Label("Remote", systemImage: "network").searchCompletion(JobSearchToken.remoteType(.remote))
            Label("Hybrid", systemImage: "network").searchCompletion(JobSearchToken.remoteType(.hybrid))
            Label("On-site", systemImage: "network").searchCompletion(JobSearchToken.remoteType(.onsite))
        }

        // Fit score suggestions
        if q.hasPrefix("fit") || q.hasPrefix(">") || q.hasPrefix("f") {
            Label("Fit ≥ 55", systemImage: "chart.bar").searchCompletion(JobSearchToken.minFitScore(55))
            Label("Fit ≥ 70", systemImage: "chart.bar").searchCompletion(JobSearchToken.minFitScore(70))
            Label("Fit ≥ 85", systemImage: "chart.bar").searchCompletion(JobSearchToken.minFitScore(85))
        }

        // Salary suggestions
        if q.hasPrefix("$") || q.hasPrefix("sal") {
            Label("Salary ≥ $100k", systemImage: "dollarsign").searchCompletion(JobSearchToken.minSalary(100_000))
            Label("Salary ≥ $150k", systemImage: "dollarsign").searchCompletion(JobSearchToken.minSalary(150_000))
            Label("Salary ≥ $200k", systemImage: "dollarsign").searchCompletion(JobSearchToken.minSalary(200_000))
        }

        // Rating suggestions
        if q.hasPrefix("★") || q.hasPrefix("rat") || q.hasPrefix("star") {
            Label("Rating ≥ 3★", systemImage: "star").searchCompletion(JobSearchToken.minRating(3))
            Label("Rating ≥ 4★", systemImage: "star").searchCompletion(JobSearchToken.minRating(4))
            Label("Rating ≥ 5★", systemImage: "star").searchCompletion(JobSearchToken.minRating(5))
        }

        // The user's own companies and titles. Placed after the structured tokens: those are exact
        // and few, and burying them under a long list of company names would make the token system
        // harder to discover than it already is.
        ForEach(dataSuggestions) { suggestion in
            Label(
                suggestion.text,
                systemImage: suggestion.kind == .company ? "building.2" : "briefcase"
            )
            .searchCompletion(suggestion.text)
        }

        // Recent days suggestions
        if q.hasPrefix("rec") || q.hasPrefix("last") || q.hasPrefix("new") {
            Label("Last 7 days", systemImage: "calendar").searchCompletion(JobSearchToken.recentDays(7))
            Label("Last 30 days", systemImage: "calendar").searchCompletion(JobSearchToken.recentDays(30))
            Label("Last 90 days", systemImage: "calendar").searchCompletion(JobSearchToken.recentDays(90))
        }
    }

    /// Selecting one inserts the plain text, which the existing freetext matcher already applies to
    /// `displayCompany` and `displayTitle` — no new filter path, so a suggestion can't disagree with
    /// what typing the same string would have done.
    private var dataSuggestions: [JobTextSuggestions.Suggestion] {
        JobTextSuggestions.suggest(
            prefix: searchText,
            companies: allJobs.compactMap(\.displayCompany),
            titles: allJobs.compactMap(\.displayTitle)
        )
    }
}
