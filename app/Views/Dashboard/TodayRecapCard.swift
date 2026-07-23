import JobhuntCore
import SwiftData
import SwiftUI

// MARK: - TodayRecapCard (TASK-623)

/// A humane end-of-day recap of the meaningful work the user did today, plus a 7-day progress strip.
/// Every total is auditable: tapping a metric or a day opens the jobs behind it. Aggregation lives in
/// `DashboardMetrics`; the momentum line is warm and non-comparative — no streaks, quotas, or guilt.
/// Self-contained: owns the event / completed-follow-up queries and navigates via the router.
struct TodayRecapCard: View {
    /// Start-of-day token (from the Dashboard) so the recap advances at local midnight.
    let day: Date

    @Environment(Router.self) private var router
    @Query private var events: [JobEvent]
    @Query(filter: #Predicate<JobAction> { $0.completedAt != nil }) private var completedActions: [JobAction]

    @State private var drilldown: Drilldown?

    /// A requested drill-in: a day, optionally focused on one category (from a tapped metric).
    private struct Drilldown: Identifiable {
        let id: String
        let day: Date
        let focus: DayActivity.Category?
    }

    private var recapEvents: [DashboardMetrics.RecapEvent] {
        events.map {
            .init(
                eventType: $0.eventType, note: $0.note, occurredAt: $0.occurredAt,
                jobID: $0.job?.id, jobNumber: $0.job?.jobNumber, company: $0.job?.company, title: $0.job?.title
            )
        }
    }

    private var followUps: [DashboardMetrics.FollowUpCompletion] {
        completedActions.compactMap { action in
            action.completedAt.map {
                .init(
                    completedAt: $0, jobID: action.job?.id, jobNumber: action.job?.jobNumber,
                    company: action.job?.company, title: action.job?.title
                )
            }
        }
    }

    private var followUpDates: [Date] { followUps.map(\.completedAt) }

    private var recap: DailyRecap {
        DashboardMetrics.buildDailyRecap(events: recapEvents, followUpCompletions: followUpDates, day: day)
    }

    /// Meaningful-action totals for the last 7 days (oldest → newest), for the progress strip.
    private var week: [(day: Date, total: Int)] {
        DashboardMetrics.buildRecapWindow(
            events: recapEvents, followUpCompletions: followUpDates, days: 7, endingOn: day
        )
    }

    private func dayActivity(for target: Date) -> DayActivity {
        DashboardMetrics.buildDayActivity(events: recapEvents, followUps: followUps, day: target)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Today")
                .font(.headline)
                .foregroundStyle(.primary)

            GroupBox {
                VStack(alignment: .leading, spacing: 12) {
                    if recap.hasActivity { todayBreakdown } else { emptyToday }
                    if week.contains(where: { $0.total > 0 }) {
                        Divider()
                        weekStrip
                    }
                }
            }
        }
        .sheet(item: $drilldown) { target in
            DayActivitySheet(
                activity: dayActivity(for: target.day),
                focus: target.focus,
                onSelectJob: { jobID in
                    drilldown = nil
                    router.selectedJobID = jobID
                    router.selectedSection = .jobs
                }
            )
        }
    }

    private var todayBreakdown: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(momentumLine(recap.total))
                .font(.subheadline.weight(.medium))
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 180), alignment: .leading)],
                alignment: .leading, spacing: 8
            ) {
                metric(recap.captured, .found)
                metric(recap.movedToInterested, .movedToInterested)
                metric(recap.applied, .applied)
                metric(recap.interviews, .interview)
                metric(recap.offers, .offer)
                metric(recap.triaged, .triaged)
                metric(recap.duplicatesResolved, .duplicateResolved)
                metric(recap.notesAdded, .note)
                metric(recap.followUpsCompleted, .followUp)
            }
        }
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var emptyToday: some View {
        VStack(spacing: 6) {
            Text("No tracked activity yet today.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text("Capture, triage, or apply to a job and it'll show up here.")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }

    /// One tappable recap metric, rendered only when `count > 0`; tapping drills into today's jobs for
    /// that category.
    @ViewBuilder
    private func metric(_ count: Int, _ category: DayActivity.Category) -> some View {
        if count > 0 {
            Button {
                drilldown = Drilldown(id: "\(day.timeIntervalSinceReferenceDate)-\(category.rawValue)",
                                      day: day, focus: category)
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: category.symbol).foregroundStyle(Theme.accent).frame(width: 18)
                    Text("\(count)").font(.body.weight(.semibold)).monospacedDigit()
                    Text(category.label).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                    Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.tertiary)
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(count) \(category.label), show jobs")
        }
    }

    /// A compact "last 7 days" strip: one bar per day (height ∝ meaningful actions), today accented.
    /// Tapping a day with activity drills into that day's jobs.
    private var weekStrip: some View {
        let totals = week
        let maxTotal = max(totals.map(\.total).max() ?? 0, 1)
        return VStack(alignment: .leading, spacing: 6) {
            Text("Last 7 days")
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
            HStack(alignment: .bottom, spacing: 10) {
                ForEach(totals, id: \.day) { entry in
                    dayBar(entry, maxTotal: maxTotal)
                }
            }
        }
    }

    @ViewBuilder
    private func dayBar(_ entry: (day: Date, total: Int), maxTotal: Int) -> some View {
        let isToday = Calendar.current.isDate(entry.day, inSameDayAs: day)
        let plural = entry.total == 1 ? "" : "s"
        Button {
            if entry.total > 0 {
                drilldown = Drilldown(id: "\(entry.day.timeIntervalSinceReferenceDate)-all", day: entry.day, focus: nil)
            }
        } label: {
            VStack(spacing: 4) {
                Text("\(entry.total)")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(entry.total > 0 ? .secondary : .tertiary)
                RoundedRectangle(cornerRadius: 3)
                    .fill(barColor(total: entry.total, isToday: isToday))
                    .frame(height: 6 + CGFloat(entry.total) / CGFloat(maxTotal) * 40)
                Text(weekdayLetter(entry.day))
                    .font(.caption2)
                    .foregroundStyle(isToday ? .primary : .secondary)
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(entry.total == 0)
        .accessibilityLabel("\(weekdayLabel(entry.day)): \(entry.total) action\(plural)")
    }

    private func barColor(total: Int, isToday: Bool) -> Color {
        guard total > 0 else { return Color.secondary.opacity(0.15) }
        return isToday ? Theme.accent : Theme.accent.opacity(0.45)
    }

    private func weekdayLetter(_ date: Date) -> String {
        let symbols = Calendar.current.veryShortWeekdaySymbols
        return symbols[Calendar.current.component(.weekday, from: date) - 1]
    }

    private func weekdayLabel(_ date: Date) -> String {
        date.formatted(.dateTime.weekday(.abbreviated))
    }

    /// Warm, non-comparative momentum line — no streaks, quotas, or guilt (TASK-623).
    private func momentumLine(_ total: Int) -> String {
        switch total {
        case 1: "You got 1 thing done today — every step counts."
        case 2 ... 4: "Nice — \(total) meaningful actions today."
        default: "Strong day — \(total) meaningful actions. 👏"
        }
    }
}

// MARK: - DayActivitySheet

/// The jobs behind a day's recap totals, grouped by category. Opened from a metric (focused on one
/// category) or a day bar (all categories); each row navigates to the job (TASK-623, AC #4/#10).
private struct DayActivitySheet: View {
    let activity: DayActivity
    let focus: DayActivity.Category?
    let onSelectJob: (String) -> Void

    @Environment(\.dismiss) private var dismiss

    private var sections: [DayActivity.Section] {
        guard let focus else { return activity.sections }
        return activity.sections.filter { $0.category == focus }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(activity.day.formatted(date: .complete, time: .omitted))
                    .font(.headline)
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding()
            Divider()

            if sections.isEmpty {
                Spacer()
                Text("Nothing tracked on this day.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                Spacer()
            } else {
                List {
                    ForEach(sections) { section in
                        Section {
                            ForEach(section.items) { item in
                                row(item)
                            }
                        } header: {
                            Label("\(section.items.count) \(section.category.label)",
                                  systemImage: section.category.symbol)
                        }
                    }
                }
            }
        }
        .frame(width: 460, height: 520)
    }

    @ViewBuilder
    private func row(_ item: DayActivity.Item) -> some View {
        Button {
            if let jobID = item.jobID { onSelectJob(jobID) }
        } label: {
            HStack(spacing: 8) {
                if let number = item.jobNumber {
                    Text("#\(number)").font(.caption.monospacedDigit()).foregroundStyle(.tertiary)
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text(item.title ?? "Untitled").font(.subheadline).lineLimit(1)
                    if let company = item.company, !company.isEmpty {
                        Text(company).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
                Spacer()
                if item.jobID != nil {
                    Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.tertiary)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(item.jobID == nil)
    }
}
