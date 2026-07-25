import JobhuntCore
import SwiftData
import SwiftUI

// MARK: - DashboardMilestoneCard (TASK-646)

/// Upcoming interviews and offer decision deadlines. Before this, TASK-501's structured milestones were
/// only visible inside the job they belonged to — so an interview next Tuesday, or an offer deadline,
/// never resurfaced on its own while stale *referrals* did nag. This puts the highest-stakes dates in
/// the funnel where they can't be missed.
///
/// Self-contained (owns its queries, navigates via the router) like `DashboardReferralCard`; selection
/// and ordering come from `MilestoneSchedule` so this card and Needs Action can't drift.
struct DashboardMilestoneCard: View {
    @Environment(Router.self) private var router
    @Query private var jobs: [Job]
    @Query private var interviews: [InterviewRecord]
    @Query private var offers: [OfferRecord]

    private var jobsByID: [String: Job] {
        Dictionary(jobs.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    }

    private var upcoming: [(job: Job, interview: InterviewRecord)] {
        let byID = jobsByID
        let projected = interviews.compactMap { record -> MilestoneSchedule.Interview? in
            guard let job = byID[record.jobID] else { return nil }
            return .init(
                jobID: record.jobID, scheduledAt: record.scheduledAt,
                kind: InterviewKind(rawValue: record.kind) ?? .other,
                interviewer: record.interviewer, jobIsTerminal: job.status.isTerminal
            )
        }
        let ordered = MilestoneSchedule.upcomingInterviews(projected, now: Date())
        // Re-associate with the live records for display, preserving the schedule's ordering.
        return ordered.compactMap { entry in
            guard let job = byID[entry.jobID],
                  let record = interviews.first(where: {
                      $0.jobID == entry.jobID && $0.scheduledAt == entry.scheduledAt
                  })
            else { return nil }
            return (job, record)
        }
    }

    private var deadlines: [(job: Job, offer: OfferRecord)] {
        let byID = jobsByID
        let projected = offers.compactMap { record -> MilestoneSchedule.OfferDeadline? in
            guard let job = byID[record.jobID], let decisionBy = record.decisionBy else { return nil }
            return .init(
                jobID: record.jobID, decisionBy: decisionBy,
                title: record.title, jobIsTerminal: job.status.isTerminal
            )
        }
        return MilestoneSchedule.offerDeadlines(projected, now: Date()).compactMap { entry in
            guard let job = byID[entry.jobID],
                  let record = offers.first(where: { $0.jobID == entry.jobID })
            else { return nil }
            return (job, record)
        }
    }

    var body: some View {
        let interviewList = Array(upcoming.prefix(5))
        let deadlineList = Array(deadlines.prefix(3))
        if !interviewList.isEmpty || !deadlineList.isEmpty {
            card(interviewList: interviewList, deadlineList: deadlineList)
        }
    }

    private func card(
        interviewList: [(job: Job, interview: InterviewRecord)],
        deadlineList: [(job: Job, offer: OfferRecord)]
    ) -> some View {
        let now = Date()
        return GroupBox {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 6) {
                    Image(systemName: "calendar.badge.clock").font(.caption).foregroundStyle(.blue)
                    Text("Interviews & offers").font(.subheadline.weight(.semibold))
                    Spacer()
                }
                .padding(.bottom, 10)

                ForEach(deadlineList, id: \.offer.id) { entry in
                    row(
                        job: entry.job,
                        title: entry.offer.title ?? "Offer",
                        detail: deadlineText(entry.offer.decisionBy ?? now, now: now),
                        symbol: "checkmark.seal",
                        tint: deadlineTint(entry.offer.decisionBy ?? now, now: now)
                    )
                    if entry.offer.id != deadlineList.last?.offer.id || !interviewList.isEmpty { Divider() }
                }

                ForEach(interviewList, id: \.interview.id) { entry in
                    row(
                        job: entry.job,
                        title: (InterviewKind(rawValue: entry.interview.kind) ?? .other).label,
                        detail: interviewText(entry.interview, now: now),
                        symbol: "person.2",
                        tint: MilestoneSchedule.urgency(of: entry.interview.scheduledAt, now: now) == .today
                            ? .orange : .secondary
                    )
                    if entry.interview.id != interviewList.last?.interview.id { Divider() }
                }
            }
            .padding(4)
        }
    }

    private func row(job: Job, title: String, detail: String, symbol: String, tint: Color) -> some View {
        Button {
            router.selectedJobID = job.id
            router.selectedSection = .jobs
        } label: {
            HStack(spacing: 8) {
                Image(systemName: symbol).font(.caption).foregroundStyle(tint).frame(width: 16)
                VStack(alignment: .leading, spacing: 1) {
                    Text(job.company ?? "Unknown")
                        .font(.caption.weight(.semibold)).foregroundStyle(.primary).lineLimit(1)
                    Text("\(title) · \(detail)")
                        .font(.caption2).foregroundStyle(tint == .secondary ? .secondary : tint).lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.tertiary)
            }
            .padding(.vertical, 7).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(job.company ?? "Unknown"), \(title), \(detail)")
    }

    private func interviewText(_ interview: InterviewRecord, now: Date) -> String {
        switch MilestoneSchedule.urgency(of: interview.scheduledAt, now: now) {
        case .today: "today \(interview.scheduledAt.formatted(date: .omitted, time: .shortened))"
        case .overdue, .soon, .later:
            interview.scheduledAt.formatted(date: .abbreviated, time: .shortened)
        }
    }

    private func deadlineText(_ decisionBy: Date, now: Date) -> String {
        let days = MilestoneSchedule.daysRemaining(until: decisionBy, now: now)
        return switch MilestoneSchedule.urgency(of: decisionBy, now: now) {
        case .overdue: "decision was due \(-days)d ago"
        case .today: "decide today"
        case .soon, .later: "decide in \(days)d"
        }
    }

    private func deadlineTint(_ decisionBy: Date, now: Date) -> Color {
        switch MilestoneSchedule.urgency(of: decisionBy, now: now) {
        case .overdue, .today: .red
        case .soon: .orange
        case .later: .secondary
        }
    }
}
