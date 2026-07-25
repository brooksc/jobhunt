import JobhuntCore
import SwiftUI

// MARK: - Needs Action milestones (TASK-646)

/// Scheduled interviews and offer decision deadlines, shown above the follow-up buckets.
///
/// Deliberately a *separate* section rather than folded into the Overdue/Today/This-week buckets: those
/// rows are follow-ups you complete or snooze, and an interview is neither — you can't "complete" a
/// Tuesday onsite. Mixing them would break the screen's bulk actions and its meaning. These rows are
/// read-only pointers into the job.
struct NeedsActionMilestonesSection: View {
    let interviews: [(job: Job, record: InterviewRecord)]
    let offers: [(job: Job, record: OfferRecord)]
    let onSelectJob: (String) -> Void

    var body: some View {
        if !interviews.isEmpty || !offers.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Image(systemName: "calendar.badge.clock").font(.caption).foregroundStyle(.blue)
                    Text("Scheduled").font(.subheadline.weight(.semibold))
                    Spacer()
                }
                let now = Date()
                ForEach(offers, id: \.record.id) { entry in
                    if let decisionBy = entry.record.decisionBy {
                        row(
                            job: entry.job, symbol: "checkmark.seal",
                            title: entry.record.title ?? "Offer",
                            detail: MilestoneCopy.deadlineText(decisionBy, now: now),
                            tint: MilestoneCopy.tint(for: decisionBy, now: now)
                        )
                    }
                }
                ForEach(interviews, id: \.record.id) { entry in
                    row(
                        job: entry.job, symbol: "person.2",
                        title: (InterviewKind(rawValue: entry.record.kind) ?? .other).label,
                        detail: MilestoneCopy.interviewText(entry.record.scheduledAt, now: now),
                        tint: MilestoneSchedule.urgency(of: entry.record.scheduledAt, now: now) == .today
                            ? .orange : .secondary
                    )
                }
            }
        }
    }

    private func row(job: Job, symbol: String, title: String, detail: String, tint: Color) -> some View {
        Button { onSelectJob(job.id) } label: {
            HStack(spacing: 12) {
                Text(detail)
                    .font(.caption.monospacedDigit().weight(.semibold))
                    .foregroundStyle(tint)
                    .frame(width: 96, alignment: .leading)
                Image(systemName: symbol).font(.caption).foregroundStyle(tint).frame(width: 16)
                VStack(alignment: .leading, spacing: 1) {
                    Text(job.displayCompany ?? "Unknown")
                        .font(.callout.weight(.medium)).lineLimit(1)
                    Text("\(title) · \(job.displayTitle)")
                        .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.tertiary)
            }
            .padding(.vertical, 7).padding(.horizontal, 10).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(job.displayCompany ?? "Unknown"), \(title), \(detail)")
    }
}

/// Shared wording/colour for milestone dates, so the Dashboard card and Needs Action read identically.
enum MilestoneCopy {
    static func interviewText(_ scheduledAt: Date, now: Date) -> String {
        switch MilestoneSchedule.urgency(of: scheduledAt, now: now) {
        case .today: "Today"
        case .soon, .later, .overdue:
            scheduledAt.formatted(.dateTime.month(.abbreviated).day())
        }
    }

    static func deadlineText(_ decisionBy: Date, now: Date) -> String {
        let days = MilestoneSchedule.daysRemaining(until: decisionBy, now: now)
        return switch MilestoneSchedule.urgency(of: decisionBy, now: now) {
        case .overdue: "\(-days)d overdue"
        case .today: "Today"
        case .soon, .later: "in \(days)d"
        }
    }

    static func tint(for decisionBy: Date, now: Date) -> Color {
        switch MilestoneSchedule.urgency(of: decisionBy, now: now) {
        case .overdue, .today: .red
        case .soon: .orange
        case .later: .secondary
        }
    }
}
