import JobhuntCore
import SwiftData
import SwiftUI

// MARK: - Market sweep

extension SearchSettingsTab {
    /// The whole-market sweep and its progress (TASK-696).
    ///
    /// Its own section because it is a different bargain from watching named companies: tens of
    /// thousands of requests over hours rather than a handful a day. And it needs a progress
    /// readout for a reason the other loops don't — a pass takes long enough that, without one,
    /// "running" and "stuck" look identical for most of a day.
    var marketSection: some View {
        Section("Search every company") {
            Toggle("Sweep all public job boards", isOn: Binding(
                get: { settings.bool(forKey: SettingsKey.marketSweepEnabled) },
                set: { settings.setBool($0, forKey: SettingsKey.marketSweepEnabled) }
            ))

            Text(
                "Walks the ~29,000 public Greenhouse, Lever, Ashby and Workday boards rather than "
                    + "only the companies above. This is how you find a job at a company you've "
                    + "never heard of. It runs slowly in the background over several hours, resumes "
                    + "where it left off, and goes gently on any board that asks it to."
            )
            .font(.caption)
            .foregroundStyle(.secondary)

            LabeledContent("Start each day at") {
                Picker("Start each day at", selection: Binding(
                    get: { settings.int(forKey: SettingsKey.marketSweepStartHour) },
                    set: { settings.setInt($0, forKey: SettingsKey.marketSweepStartHour) }
                )) {
                    ForEach(0 ..< 24, id: \.self) { hour in
                        Text(String(format: "%02d:00", hour)).tag(hour)
                    }
                }
                .labelsHidden()
                .frame(width: 110)
            }
            Text("A pass takes a few hours, so an early start means it has finished by the time you "
                + "sit down. A fixed hour rather than a gap after the last one — otherwise the start "
                + "time creeps later every day.")
                .font(.caption)
                .foregroundStyle(.secondary)

            if let state = marketState.first {
                marketProgress(state)
            } else if settings.bool(forKey: SettingsKey.marketSweepEnabled) {
                marketWaitingNotice
            }
        }
    }

    /// Two different waits, and saying the wrong one sends the user looking for progress that
    /// cannot start: nothing downloads or sweeps until a title keyword exists.
    @ViewBuilder
    private var marketWaitingNotice: some View {
        if DiscoverySettings.canSweep(settings) {
            Text("Waiting to start — the board list downloads on the first run.")
                .font(.caption)
                .foregroundStyle(.secondary)
        } else {
            Text("Paused — add at least one job title above before anything is checked.")
                .font(.caption)
                .foregroundStyle(.orange)
        }
    }

    private func marketProgress(_ state: MarketSweepState) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if state.isFinished {
                Label(
                    "Finished \(state.finishedAt?.formatted(.relative(presentation: .named)) ?? "")",
                    systemImage: "checkmark.circle.fill"
                )
                .foregroundStyle(.green)
                .font(.callout)
            } else {
                ProgressView(value: state.progress) {
                    Text("Sweeping — \(state.cursor.formatted()) of \(state.boardCount.formatted()) boards")
                        .font(.callout)
                }
                // A percentage alone reads as stalled on a sweep this long; the board counts move
                // visibly even when the percentage doesn't.
                .progressViewStyle(.linear)
            }

            Text(
                "\(state.postingsSeen.formatted()) postings seen · "
                    + "\(state.postingsPassed.formatted()) matched · "
                    + "\(state.postingsIngested.formatted()) added"
                    + (state.boardsUnreachable > 0
                        ? " · \(state.boardsUnreachable.formatted()) boards unreachable" : "")
            )
            .font(.caption)
            .foregroundStyle(.secondary)

            // A pause is not a failure, but it has to be visible or the sweep looks stuck.
            if let reason = state.pauseReason {
                Label(reason, systemImage: "pause.circle")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
        .padding(.vertical, 2)
    }
}
