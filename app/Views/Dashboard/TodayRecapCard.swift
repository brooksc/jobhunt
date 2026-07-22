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

    private var recap: DailyRecap {
        DashboardMetrics.buildDailyRecap(
            events: events.map { .init(eventType: $0.eventType, note: $0.note, occurredAt: $0.occurredAt) },
            followUpCompletions: followUpCompletions,
            day: day
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Today")
                .font(.headline)
                .foregroundStyle(.primary)

            GroupBox {
                if recap.hasActivity {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(momentumLine(recap.total))
                            .font(.subheadline.weight(.medium))
                        LazyVGrid(
                            columns: [GridItem(.adaptive(minimum: 170), alignment: .leading)],
                            alignment: .leading, spacing: 10
                        ) {
                            item(recap.captured, singular: "job found",
                                 label: "Jobs found", symbol: "tray.and.arrow.down")
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
                } else {
                    VStack(spacing: 6) {
                        Text("No tracked activity yet today.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Text("Capture, triage, or apply to a job and it'll show up here.")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .frame(height: 90)
                }
            }
        }
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
