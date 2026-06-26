import Foundation

/// Single classification of where a site sits in the review cycle, shared by the dashboard
/// "Sites due" count, the dashboard Site Check-in Schedule, and the Sites screen buckets so they
/// can't disagree — e.g. a brand-new site (no `nextReviewAt`) is "not yet reviewed", NOT "due"
/// (TASK-582).
public enum SiteReviewBucket: Sendable, Equatable {
    case overdue // scheduled, review date is in the past
    case dueSoon // scheduled, review date within the due-soon window
    case scheduledLater // scheduled, review date beyond the due-soon window
    case notYetReviewed // no review date yet (and not excluded)
    case excluded // user excluded this site from review

    public static func classify(
        state: SiteState,
        nextReviewAt: Date?,
        now: Date,
        dueSoonDays: Int = 7
    ) -> SiteReviewBucket {
        if state == .exclude { return .excluded }
        guard let next = nextReviewAt else { return .notYetReviewed }
        if next < now { return .overdue }
        let soon = Calendar.current.date(byAdding: .day, value: dueSoonDays, to: now) ?? now
        return next <= soon ? .dueSoon : .scheduledLater
    }
}
