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
    ///
    /// Narrowed to discovered captures in the predicate rather than in `foundToday`: unfiltered,
    /// this fetched every capture in the library — a thousand-plus rows, growing — on every
    /// Dashboard update, to count the handful that arrived today. The date stays out of the
    /// predicate deliberately, because a `@Query` predicate is fixed when the view is created and
    /// one built around "today" would keep reporting yesterday's total after midnight.
    @Query(filter: #Predicate<Capture> { $0.discoveredBySourceID != nil })
    private var captures: [Capture]

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
        // On the structured field, not the note: the note is editable copy, so parsing it would
        // lose a find the user annotated and miscount any other note starting the same way. The
        // `discoveredBySourceID` half of that test is now the query's predicate.
        return captures.count { $0.capturedAt >= start }
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

                statusLine

                Text(summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(12)
            .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 8))
        }
    }

    /// What the card is claiming, in priority order.
    ///
    /// Derived as one value rather than a chain of `if`s in the view, because the earlier version
    /// treated any unfinished sweep row as "checking" — so it reported scanning as healthy while
    /// the sweep was disabled, rate-limited, budget-paused or misconfigured. A status surface that
    /// can say "working" when nothing is working is worse than no status surface.
    enum Status: Equatable {
        case needsCriteria
        case paused(String)
        case nothingConfigured
        case sweeping(done: Int, total: Int)
        case foundToday(Int)
        case idle
    }

    var status: Status {
        if blocked {
            return .needsCriteria
        }
        if foundToday > 0 {
            return .foundToday(foundToday)
        }

        let marketOn = settings.bool(forKey: SettingsKey.marketSweepEnabled)
        let activeSources = sources.count { $0.enabled }
        if !marketOn, activeSources == 0 {
            return .nothingConfigured
        }

        // A pause is only meaningful while the market sweep is the thing running.
        if marketOn, let state, !state.isFinished {
            if let reason = state.pauseReason {
                return .paused(reason)
            }
            return .sweeping(done: state.cursor, total: state.boardCount)
        }
        if let source = sources.first(where: { $0.enabled && $0.status.needsAttention }) {
            return .paused("\(source.label): \(source.status.rawValue)")
        }
        return .idle
    }

    @ViewBuilder
    private var statusLine: some View {
        switch status {
        case .needsCriteria:
            Label(
                "Paused — add at least one job title so it knows what to look for.",
                systemImage: "exclamationmark.triangle.fill"
            )
            .font(.callout)
            .foregroundStyle(.orange)
        case let .paused(reason):
            Label(reason, systemImage: "pause.circle.fill")
                .font(.callout)
                .foregroundStyle(.orange)
        case .nothingConfigured:
            Label(
                "No companies watched and no full search running — nothing is being checked.",
                systemImage: "questionmark.circle"
            )
            .font(.callout)
            .foregroundStyle(.orange)
        case let .sweeping(done, total):
            // Boards rather than a percentage: on a pass this long the percentage barely moves,
            // and a number that doesn't move reads as stuck.
            Label(
                "Checking company job boards — \(done.formatted()) of \(total.formatted()) so far",
                systemImage: "arrow.triangle.2.circlepath"
            )
            .font(.callout)
        case let .foundToday(count):
            Label(
                "\(count) new job\(count == 1 ? "" : "s") found today",
                systemImage: "sparkles"
            )
            .font(.callout)
            .foregroundStyle(.green)
        case .idle:
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
        } else if settings.bool(forKey: SettingsKey.marketSweepEnabled), !blocked {
            // Only when it can actually start. The status line already says the interlock is
            // closed; claiming a first check is "starting" underneath it contradicts that.
            parts.append("starting the first full check of every public job board")
        }
        return parts.isEmpty ? "No sources configured yet." : parts.joined(separator: " · ")
    }
}
