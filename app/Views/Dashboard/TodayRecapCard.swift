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

    private var followUpDates: [Date] {
        followUps.map(\.completedAt)
    }

    private var recap: DailyRecap {
        DashboardMetrics.buildDailyRecap(events: recapEvents, followUpCompletions: followUpDates, day: day)
    }

    /// Meaningful-action totals for the last 7 days (oldest → newest), for the progress strip.
    /// Selectable look-back window for the activity strip (AC #4).
    private enum RecapRange: Int, CaseIterable, Identifiable {
        case week = 7, month = 30
        var id: Int {
            rawValue
        }

        var label: String {
            self == .week ? "7 days" : "30 days"
        }
    }

    @State private var range: RecapRange = .week
    @State private var showCloseOut = false

    private func totals(days: Int) -> [(day: Date, total: Int)] {
        DashboardMetrics.buildRecapWindow(
            events: recapEvents, followUpCompletions: followUpDates, days: days, endingOn: day
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

                    // TASK-623 #3: an explicit place to stop for the day. Separate from the always-on
                    // card because closing out is a deliberate act — the point is a moment of
                    // closure, not another number on a dashboard.
                    HStack {
                        Button("Close Out My Day…") { showCloseOut = true }
                            .buttonStyle(.link)
                            .help("A written summary of what you got done today")
                        Spacer()
                    }
                    // Offer the strip whenever there's any activity across the longest window.
                    if totals(days: RecapRange.month.rawValue).contains(where: { $0.total > 0 }) {
                        Divider()
                        activityStrip
                    }
                }
            }
        }
        .sheet(isPresented: $showCloseOut) {
            CloseOutDaySheet(
                recap: recap,
                weekTotals: totals(days: RecapRange.week.rawValue),
                monthTotals: totals(days: RecapRange.month.rawValue),
                onSelectDay: { selected in
                    showCloseOut = false
                    drilldown = Drilldown(
                        id: "\(selected.timeIntervalSinceReferenceDate)-all", day: selected, focus: nil
                    )
                }
            )
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
                metric(recap.referralsRequested, .referralRequested)
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
                drilldown = Drilldown(
                    id: "\(day.timeIntervalSinceReferenceDate)-\(category.rawValue)",
                    day: day,
                    focus: category
                )
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

    /// The activity strip: one bar per day over the selected window (7 or 30 days), height ∝ meaningful
    /// actions, today accented. Tapping a day with activity drills into its jobs. Per-day count/weekday
    /// labels show only in the compact 7-day view (30 bars are too narrow to label).
    private var activityStrip: some View {
        let entries = totals(days: range.rawValue)
        let maxTotal = max(entries.map(\.total).max() ?? 0, 1)
        let compact = range == .week
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Last \(range.label)")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                Spacer()
                Picker("Range", selection: $range) {
                    ForEach(RecapRange.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
                .controlSize(.small)
            }
            HStack(alignment: .bottom, spacing: compact ? 10 : 3) {
                ForEach(entries, id: \.day) { entry in
                    dayBar(entry, maxTotal: maxTotal, showLabels: compact)
                }
            }
        }
    }

    @ViewBuilder
    private func dayBar(_ entry: (day: Date, total: Int), maxTotal: Int, showLabels: Bool) -> some View {
        let isToday = Calendar.current.isDate(entry.day, inSameDayAs: day)
        let plural = entry.total == 1 ? "" : "s"
        Button {
            if entry.total > 0 {
                drilldown = Drilldown(id: "\(entry.day.timeIntervalSinceReferenceDate)-all", day: entry.day, focus: nil)
            }
        } label: {
            VStack(spacing: 4) {
                if showLabels {
                    Text("\(entry.total)")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(entry.total > 0 ? .secondary : .tertiary)
                }
                RoundedRectangle(cornerRadius: showLabels ? 3 : 1.5)
                    .fill(barColor(total: entry.total, isToday: isToday))
                    .frame(height: 6 + CGFloat(entry.total) / CGFloat(maxTotal) * 40)
                if showLabels {
                    Text(weekdayLetter(entry.day))
                        .font(.caption2)
                        .foregroundStyle(isToday ? .primary : .secondary)
                }
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(entry.total == 0)
        .help(showLabels ? "" : "\(weekdayLabel(entry.day)): \(entry.total) action\(plural)")
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
                            Label(
                                "\(section.items.count) \(section.category.label)",
                                systemImage: section.category.symbol
                            )
                        }
                    }
                }
            }
        }
        .frame(width: 460, height: 520)
    }

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
