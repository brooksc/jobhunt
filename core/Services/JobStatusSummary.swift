import Foundation

/// Aggregated counts and short sorted lists derived from a jobs array in a single pass.
/// Used by the dashboard to avoid iterating all jobs once per section.
/// `Sendable` so `zero` can be a static let without a concurrency warning. Everything it holds is a
/// value type; `funnelCounts` needs the explicit conformance because a tuple array doesn't infer it.
public struct JobStatusSummary: @unchecked Sendable {
    public let total: Int
    public let active: Int
    public let interviews: Int
    public let offers: Int
    public let rejected: Int
    public let passed: Int
    public let issueCount: Int
    public let avgFitDisplay: String

    /// Count for each pipeline stage. Index matches the canonical funnel order.
    public let funnelCounts: [(label: String, count: Int)]

    /// Counts by status, computed in the same pass.
    public let countsByStatus: [JobStatus: Int]

    public static let zero = JobStatusSummary(jobs: [])

    public init(jobs: [Job]) {
        var byStatus = [JobStatus: Int]()
        var fitSum = 0
        var fitCount = 0
        var issues = 0

        for job in jobs {
            byStatus[job.status, default: 0] += 1
            if let score = job.fitScore, job.fitStatus == .succeeded { fitSum += score; fitCount += 1 }
            if !QualityChecker.issues(for: job).isEmpty { issues += 1 }
        }

        total = jobs.count
        active = (byStatus[.pursuing] ?? 0) + (byStatus[.applied] ?? 0) + (byStatus[.interview] ?? 0)
        interviews = byStatus[.interview] ?? 0
        offers = byStatus[.offer] ?? 0
        rejected = byStatus[.rejected] ?? 0
        passed = byStatus[.passed] ?? 0
        issueCount = issues
        countsByStatus = byStatus
        avgFitDisplay = fitCount > 0 ? "\(fitSum / fitCount)" : "—"

        let funnelStages: [(String, [JobStatus])] = [
            ("Tracked", [.pursuing, .applied, .interview, .offer]),
            ("Applied", [.applied, .interview, .offer]),
            ("Interview", [.interview, .offer]),
            ("Offer", [.offer])
        ]
        funnelCounts = funnelStages.map { label, statuses in
            (label: label, count: statuses.reduce(0) { $0 + (byStatus[$1] ?? 0) })
        }
    }
}
