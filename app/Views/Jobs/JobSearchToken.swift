import JobhuntCore
import SwiftUI

/// Structured search tokens that appear as blue chips in the search bar.
enum JobSearchToken: Identifiable, Hashable {
    case status(JobStatus)
    case minFitScore(Int)
    case minSalary(Int)
    case remoteType(RemoteType)
    case minRating(Int)
    case recentDays(Int)

    var id: String {
        switch self {
        case let .status(s): "status:\(s.rawValue)"
        case let .minFitScore(n): "fitScore:\(n)"
        case let .minSalary(n): "salary:\(n)"
        case let .remoteType(rt): "remote:\(rt.rawValue)"
        case let .minRating(n): "rating:\(n)"
        case let .recentDays(d): "recent:\(d)"
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

        // Recent days suggestions
        if q.hasPrefix("rec") || q.hasPrefix("last") || q.hasPrefix("new") {
            Label("Last 7 days", systemImage: "calendar").searchCompletion(JobSearchToken.recentDays(7))
            Label("Last 30 days", systemImage: "calendar").searchCompletion(JobSearchToken.recentDays(30))
            Label("Last 90 days", systemImage: "calendar").searchCompletion(JobSearchToken.recentDays(90))
        }
    }
}
