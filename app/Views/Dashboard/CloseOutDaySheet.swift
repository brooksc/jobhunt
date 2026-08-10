import JobhuntCore
import SwiftUI

/// "Close Out My Day" — a written summary of the day, and the days before it (TASK-623 #3, #4).
///
/// Deliberately a sheet you open rather than another panel on the dashboard. The value the task
/// describes is *closure*, and closure is an act: you go and look, read what you did, and stop.
/// A permanently visible version of this would be one more number to feel watched by.
struct CloseOutDaySheet: View {
    let recap: DailyRecap
    let weekTotals: [(day: Date, total: Int)]
    let monthTotals: [(day: Date, total: Int)]
    let onSelectDay: (Date) -> Void

    @State private var showMonth = false
    @Environment(\.dismiss) private var dismiss

    private var totals: [(day: Date, total: Int)] {
        showMonth ? monthTotals : weekTotals
    }

    /// Only days with something on them. A list of empty rows would turn "here's your history" into
    /// "here's everything you didn't do", which is the tone this feature exists to avoid (#9).
    private var activeDays: [(day: Date, total: Int)] {
        totals.filter { $0.total > 0 }.reversed()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Close out your day").font(.headline)

            // #3: prose, not a counter. "You sent 3 applications and shortlisted 2 roles" reads like
            // something you did; "applied: 3" reads like a dashboard.
            Text(recap.recapSentence)
                .font(.title3)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityLabel(recap.recapSentence)

            if !recap.hasActivity {
                // #9: neutral, and no streak language anywhere. A day without job-hunting is a
                // normal day; the app has no business having an opinion about it.
                Text("That's fine — plenty of days look like this. Nothing here is a streak.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Divider()

            HStack {
                Text("Recent days").font(.subheadline.weight(.medium))
                Spacer()
                // #4: at least 7 and 30 days.
                Picker("Range", selection: $showMonth) {
                    Text("7 days").tag(false)
                    Text("30 days").tag(true)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 160)
            }

            if activeDays.isEmpty {
                Text("No tracked activity in this period.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                List(activeDays, id: \.day) { entry in
                    Button { onSelectDay(entry.day) } label: {
                        HStack {
                            Text(entry.day.formatted(date: .abbreviated, time: .omitted))
                            Spacer()
                            Text("\(entry.total) action\(entry.total == 1 ? "" : "s")")
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                            Image(systemName: "chevron.right")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    // #12: one stop per row, and it says what activating it does.
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(
                        "\(entry.day.formatted(date: .complete, time: .omitted)): "
                            + "\(entry.total) action\(entry.total == 1 ? "" : "s"). Show them."
                    )
                }
                .listStyle(.inset)
                .frame(minHeight: 220)
            }

            HStack {
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 520)
    }
}
