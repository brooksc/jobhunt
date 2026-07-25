import Foundation

// MARK: - MilestoneSchedule (TASK-646)

/// Which interviews and offer deadlines are worth surfacing outside the job detail, and in what order.
///
/// Pure and SwiftData-free so the selection rules are unit-testable and can't drift between the
/// Dashboard card and Needs Action — the same reason `FollowUpVisibility` (TASK-577) exists. Terminal
/// jobs are excluded here for the same reason they're excluded from follow-ups and referral nudges:
/// chasing an interview for a job you've archived is noise.
public enum MilestoneSchedule {
    /// A scheduled interview, projected off `InterviewRecord`.
    public struct Interview: Sendable, Equatable {
        public let jobID: String
        public let scheduledAt: Date
        public let kind: InterviewKind
        public let interviewer: String?
        public let jobIsTerminal: Bool

        public init(
            jobID: String, scheduledAt: Date, kind: InterviewKind,
            interviewer: String? = nil, jobIsTerminal: Bool = false
        ) {
            self.jobID = jobID
            self.scheduledAt = scheduledAt
            self.kind = kind
            self.interviewer = interviewer
            self.jobIsTerminal = jobIsTerminal
        }
    }

    /// An offer with a decision deadline, projected off `OfferRecord`.
    public struct OfferDeadline: Sendable, Equatable {
        public let jobID: String
        public let decisionBy: Date
        public let title: String?
        public let jobIsTerminal: Bool

        public init(jobID: String, decisionBy: Date, title: String? = nil, jobIsTerminal: Bool = false) {
            self.jobID = jobID
            self.decisionBy = decisionBy
            self.title = title
            self.jobIsTerminal = jobIsTerminal
        }
    }

    /// How close a deadline is, so the UI can escalate emphasis without inventing its own thresholds.
    public enum Urgency: Sendable, Equatable {
        case overdue
        case today
        case soon // within `soonDays`
        case later

        /// Emphasis order for sorting/styling — lower is more urgent.
        public var rank: Int {
            switch self {
            case .overdue: 0
            case .today: 1
            case .soon: 2
            case .later: 3
            }
        }
    }

    /// A decision within this many days reads as `soon`.
    public static let soonDays = 3

    /// Interviews still ahead of `now`, soonest first. A finished interview stops being actionable on
    /// its own — there's nothing to remember about it once it has happened, and leaving it in the list
    /// would train the user to ignore the section.
    public static func upcomingInterviews(_ interviews: [Interview], now: Date) -> [Interview] {
        interviews
            .filter { !$0.jobIsTerminal && $0.scheduledAt >= now }
            .sorted { $0.scheduledAt < $1.scheduledAt }
    }

    /// Offer deadlines worth showing, most urgent first. Unlike interviews, a *passed* deadline is kept:
    /// an expired offer decision is exactly what the user must not miss, so it surfaces as `.overdue`
    /// rather than silently disappearing.
    public static func offerDeadlines(_ offers: [OfferDeadline], now _: Date) -> [OfferDeadline] {
        offers
            .filter { !$0.jobIsTerminal }
            .sorted { $0.decisionBy < $1.decisionBy }
    }

    /// Classify a deadline relative to `now`, on calendar-day boundaries so "today" means the user's
    /// today rather than a rolling 24 hours.
    public static func urgency(of date: Date, now: Date, calendar: Calendar = .current) -> Urgency {
        if calendar.isDate(date, inSameDayAs: now) { return .today }
        if date < now { return .overdue }
        let startOfNow = calendar.startOfDay(for: now)
        let startOfDate = calendar.startOfDay(for: date)
        let days = calendar.dateComponents([.day], from: startOfNow, to: startOfDate).day ?? 0
        return days <= soonDays ? .soon : .later
    }

    /// Whole calendar days from `now` until `date` (negative once past). Drives "in 3 days" / "2 days
    /// ago" copy without each call site redoing calendar math.
    public static func daysRemaining(until date: Date, now: Date, calendar: Calendar = .current) -> Int {
        calendar.dateComponents(
            [.day], from: calendar.startOfDay(for: now), to: calendar.startOfDay(for: date)
        ).day ?? 0
    }
}
