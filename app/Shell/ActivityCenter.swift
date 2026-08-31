import Foundation
import JobhuntCore
import Observation
import SwiftUI

/// What background work is happening right now, for the window's status bar (TASK-704).
///
/// **Why this exists rather than each screen reporting itself.** Jobhunt runs four things
/// unattended — the market sweep, the extraction queue, availability checks, duplicate scans — and
/// until now each announced itself somewhere different: the Dashboard card, a settings pane, a
/// modal dialog, a toast that fades. None of them is visible from wherever the user happens to be,
/// so "is anything happening?" was a question you could only answer by opening the right screen.
///
/// The HIG position on this is that ongoing background activity belongs in a persistent, quiet
/// place — Finder's status bar, Mail's activity area — not in an alert or a floating panel, which
/// are for things that need an answer. So one observable collects it and one bar renders it.
@MainActor
@Observable
final class ActivityCenter {
    /// One unit of background work. `total <= 0` renders an indeterminate spinner, per the HIG rule
    /// that a determinate bar must not invent a completion it doesn't know.
    struct Activity: Identifiable, Equatable {
        let id: String
        var title: String
        /// The quiet second line: counts, findings so far. Nil when there is nothing to add.
        var detail: String?
        var current: Int = 0
        var total: Int = 0
        var symbol: String
        /// Where clicking the bar should take the user, when there is somewhere useful.
        var section: SidebarSection?

        var isDeterminate: Bool {
            total > 0
        }

        var fraction: Double {
            total > 0 ? min(1, max(0, Double(current) / Double(total))) : 0
        }
    }

    /// Active work, in the order it started. The bar shows the first and counts the rest.
    private(set) var activities: [Activity] = []

    var isBusy: Bool {
        !activities.isEmpty
    }

    /// The one shown in the bar. First-started wins rather than most-recent, so a long sweep isn't
    /// repeatedly displaced by short tasks starting and finishing under it.
    var primary: Activity? {
        activities.first
    }

    func begin(_ activity: Activity) {
        if let index = activities.firstIndex(where: { $0.id == activity.id }) {
            activities[index] = activity
        } else {
            activities.append(activity)
        }
    }

    /// Update in place. A no-op for an id that has already ended, so a late progress callback from
    /// a cancelled task can't resurrect a finished row.
    func update(_ id: String, _ mutate: (inout Activity) -> Void) {
        guard let index = activities.firstIndex(where: { $0.id == id }) else { return }
        mutate(&activities[index])
    }

    func end(_ id: String) {
        activities.removeAll { $0.id == id }
    }

    // MARK: - Market sweep

    /// Progress is reported against the WHOLE pass, not the current slice. The pass is what the
    /// user is waiting on, and a bar that fills every few minutes and resets says nothing about how
    /// far through 20,000 boards they are.
    func beginMarketSweep(cursor: Int, total: Int) {
        begin(Activity(
            id: TaskID.marketSweep,
            title: "Searching job boards",
            current: cursor,
            total: total,
            symbol: "binoculars",
            section: .dashboard
        ))
    }

    func reportMarketSweep(from cursor: Int, running: MarketSweepSlice) {
        update(TaskID.marketSweep) { item in
            item.current = cursor + running.boardsSwept
            item.detail = "\(running.postingsSeen.formatted()) postings"
                + (running.postingsIngested > 0 ? " · \(running.postingsIngested) added" : "")
        }
    }

    /// Stable ids, so a task started twice replaces its own row instead of stacking.
    enum TaskID {
        static let marketSweep = "market-sweep"
        static let sourceSweep = "source-sweep"
        static let extraction = "extraction"
    }
}
