import JobhuntCore
import SwiftData
import SwiftUI

/// What automatic search has been doing, on the screen the user actually opens (TASK-698).
///
/// The sweep already reported itself — in Settings → Search, which is where nobody looks. A feature
/// that works unattended for hours a day and only proves it on a settings pane is one the user has
/// no reason to trust: "found nothing today" and "hasn't run since Tuesday" are the same silence.
///
/// So this says three things and nothing else: whether it is working, what it found today, and the
/// one thing that might be stopping it. It disappears when automatic search is off, because a card
/// about a feature you turned off is just clutter.
struct AutoSearchCard: View {
    let settings: SettingsStore
    @Environment(Router.self) private var router
    @Environment(\.openSettings) private var openSettings

    @Query private var marketState: [MarketSweepState]
    @Query private var sources: [SearchSource]

    /// Jobs discovery has added today. Counted from captures rather than the ledger because this
    /// answers "what turned up for me", and a job the user already deleted should not still be
    /// claimed as today's find.
    @Query private var captures: [Capture]

    private var enabled: Bool {
        settings.bool(forKey: SettingsKey.discoveryEnabled)
            || settings.bool(forKey: SettingsKey.marketSweepEnabled)
    }

    /// The interlock, restated where the user will see it. An empty title list matches everything,
    /// so nothing sweeps until there is one — and an enabled feature doing nothing needs to say why.
    private var blocked: Bool {
        !DiscoverySettings.canSweep(settings)
    }

    private var foundToday: Int {
        let start = Calendar.current.startOfDay(for: Date())
        return captures.count {
            $0.capturedAt >= start && ($0.userNote?.hasPrefix("Found automatically") ?? false)
        }
    }

    private var state: MarketSweepState? {
        marketState.first
    }

    var body: some View {
        if enabled {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Label("Automatic search", systemImage: "binoculars")
                        .font(.headline)
                    Spacer()
                    Button("Settings") { router.settingsTab = .search; openSettings() }
                        .buttonStyle(.link)
                        .font(.caption)
                }

                if blocked {
                    Label(
                        "Paused — add at least one job title so it knows what to look for.",
                        systemImage: "exclamationmark.triangle.fill"
                    )
                    .font(.callout)
                    .foregroundStyle(.orange)
                } else {
                    statusLine
                }

                Text(summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(12)
            .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 8))
        }
    }

    @ViewBuilder
    private var statusLine: some View {
        if foundToday > 0 {
            Label(
                "\(foundToday) new job\(foundToday == 1 ? "" : "s") found today",
                systemImage: "sparkles"
            )
            .font(.callout)
            .foregroundStyle(.green)
        } else if let state, !state.isFinished {
            // Boards rather than a percentage: on a pass this long the percentage barely moves,
            // and a number that doesn't move reads as stuck.
            Label(
                "Checking company job boards — \(state.cursor.formatted()) of "
                    + "\(state.boardCount.formatted()) so far",
                systemImage: "arrow.triangle.2.circlepath"
            )
            .font(.callout)
        } else {
            Label("Watching — nothing new yet today", systemImage: "checkmark.circle")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    /// The one line that makes the feature legible: what it is watching, and when it last looked.
    private var summary: String {
        var parts: [String] = []
        let watched = sources.count { $0.enabled }
        if watched > 0 {
            parts.append("\(watched) compan\(watched == 1 ? "y" : "ies") watched")
        }
        if settings.bool(forKey: SettingsKey.marketSweepEnabled), let state {
            if state.isFinished, let finished = state.finishedAt {
                parts.append("all boards checked \(finished.formatted(.relative(presentation: .named)))")
            } else {
                parts.append("\(state.postingsSeen.formatted()) postings checked this pass")
            }
        } else if settings.bool(forKey: SettingsKey.marketSweepEnabled) {
            parts.append("starting the first full check of every public job board")
        }
        return parts.isEmpty ? "No sources configured yet." : parts.joined(separator: " · ")
    }
}
