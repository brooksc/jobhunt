import JobhuntCore
import SwiftUI

// MARK: - TodayRecapCard (TASK-623)

/// A humane end-of-day recap of the meaningful work the user did today. Aggregates the authoritative
/// event log (via `DashboardMetrics.buildDailyRecap`) into a `DailyRecap` and renders only the non-zero
/// categories; the momentum line is warm and non-comparative — no streaks, quotas, or guilt.
struct TodayRecapCard: View {
    let events: [JobEvent]
    let followUpCompletions: [Date]
    let day: Date

    private var recapEvents: [DashboardMetrics.RecapEvent] {
        events.map { .init(eventType: $0.eventType, note: $0.note, occurredAt: $0.occurredAt) }
    }

    private var recap: DailyRecap {
        DashboardMetrics.buildDailyRecap(events: recapEvents, followUpCompletions: followUpCompletions, day: day)
    }

    /// Meaningful-action totals for the last 7 days (oldest → newest), for the progress strip.
    private var week: [(day: Date, total: Int)] {
        DashboardMetrics.buildRecapWindow(
            events: recapEvents, followUpCompletions: followUpCompletions, days: 7, endingOn: day
        )
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
    }

    private var todayBreakdown: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(momentumLine(recap.total))
                .font(.subheadline.weight(.medium))
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 170), alignment: .leading)],
                alignment: .leading, spacing: 10
            ) {
                item(recap.captured, singular: "job found", label: "Jobs found", symbol: "tray.and.arrow.down")
                item(recap.movedToInterested, singular: "moved to Interested",
                     label: "To Interested", symbol: "bookmark")
                item(recap.applied, singular: "application", label: "Applications", symbol: "paperplane")
                item(recap.interviews, singular: "interview", label: "Interviews", symbol: "person.2")
                item(recap.offers, singular: "offer", label: "Offers", symbol: "star")
                item(recap.triaged, singular: "triaged", label: "Triaged / cleared", symbol: "tray.full")
                item(recap.duplicatesResolved, singular: "duplicate resolved",
                     label: "Duplicates resolved", symbol: "doc.on.doc")
                item(recap.notesAdded, singular: "note added", label: "Notes added", symbol: "note.text")
                item(recap.followUpsCompleted, singular: "follow-up done",
                     label: "Follow-ups done", symbol: "checkmark.circle")
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

    /// A compact "last 7 days" progress strip: one small bar per day (height ∝ meaningful actions),
    /// today accented, so continued momentum is visible at a glance.
    private var weekStrip: some View {
        let totals = week
        let maxTotal = max(totals.map(\.total).max() ?? 0, 1)
        return VStack(alignment: .leading, spacing: 6) {
            Text("Last 7 days")
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
            HStack(alignment: .bottom, spacing: 10) {
                ForEach(totals, id: \.day) { entry in
                    let isToday = Calendar.current.isDate(entry.day, inSameDayAs: day)
                    let plural = entry.total == 1 ? "" : "s"
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
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(weekdayLabel(entry.day)): \(entry.total) action\(plural)")
                }
            }
        }
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

    /// One recap row, rendered only when `count > 0`.
    @ViewBuilder
    private func item(_ count: Int, singular: String, label: String, symbol: String) -> some View {
        if count > 0 {
            HStack(spacing: 8) {
                Image(systemName: symbol)
                    .foregroundStyle(Theme.accent)
                    .frame(width: 18)
                Text("\(count)")
                    .font(.body.weight(.semibold))
                    .monospacedDigit()
                Text(label)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(count) \(singular)\(count == 1 ? "" : "s")")
        }
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
