import Foundation
import SwiftData

/// Where a market sweep has got to (TASK-696).
///
/// A full sweep walks ~29,000 boards and takes hours, so it cannot be an in-memory loop: the app
/// will be quit, slept and relaunched several times before it finishes. The cursor is persisted
/// after every batch, which makes a sweep resumable rather than restartable — the difference
/// between finishing in a day and never finishing at all.
///
/// One row, replaced each time a sweep starts. History lives in the ledger, which records what was
/// actually found; this only answers "where was I".
@Model
public final class MarketSweepState {
    public var id: String
    /// Identifies one pass over the directory. A new sweep gets a new id, so a resumed run can tell
    /// it is continuing its own work rather than someone else's.
    public var sweepID: String
    public var startedAt: Date
    public var updatedAt: Date
    public var finishedAt: Date?

    /// How far through the board list this sweep has got. The list is regenerated from the cached
    /// directory each time, so this is only meaningful alongside `boardCount`.
    public var cursor: Int
    public var boardCount: Int

    /// Running totals, for the status the user checks on.
    public var boardsSwept: Int
    public var boardsUnreachable: Int
    public var postingsSeen: Int
    public var postingsPassed: Int
    public var postingsIngested: Int

    /// Set when the sweep stopped for a reason worth showing — a cap reached, the directory being
    /// unavailable. Nil while running normally.
    public var pauseReason: String?

    public init(
        id: String = "market-sweep",
        sweepID: String = UUID().uuidString,
        startedAt: Date = Date(),
        boardCount: Int = 0
    ) {
        self.id = id
        self.sweepID = sweepID
        self.startedAt = startedAt
        updatedAt = startedAt
        finishedAt = nil
        cursor = 0
        self.boardCount = boardCount
        boardsSwept = 0
        boardsUnreachable = 0
        postingsSeen = 0
        postingsPassed = 0
        postingsIngested = 0
        pauseReason = nil
    }

    public var isFinished: Bool {
        finishedAt != nil
    }

    /// 0–1. Reported against the board list rather than elapsed time, because a sweep's pace varies
    /// by an order of magnitude between vendors and a time estimate would be a fiction.
    public var progress: Double {
        guard boardCount > 0 else { return 0 }
        return min(1, Double(cursor) / Double(boardCount))
    }

    /// Whether a new sweep is due.
    ///
    /// An unfinished sweep is *always* due — resuming it is the whole point, and a pass that never
    /// reaches the end of the directory finds nothing at the end of the directory.
    ///
    /// A finished one waits for the next occurrence of `startHour` in local time, rather than a
    /// fixed interval after it finished. "24 hours after the last one ended" drifts: a pass that
    /// takes five hours starts five hours later each day, and within a week the sweep is running
    /// through the afternoon instead of overnight. A wall-clock hour holds still, so the work lands
    /// before the user sits down.
    public func isDue(startHour: Int, now: Date = Date(), calendar: Calendar = .current) -> Bool {
        guard let finishedAt else { return true }
        // The most recent occurrence of startHour on or before `now`. Due when the last pass
        // finished before that, i.e. a scheduled start has come round since.
        let today = calendar.startOfDay(for: now)
        guard let todaysStart = calendar.date(byAdding: .hour, value: startHour, to: today) else {
            return now.timeIntervalSince(finishedAt) >= 24 * 3600
        }
        let lastStart = todaysStart <= now
            ? todaysStart
            : calendar.date(byAdding: .day, value: -1, to: todaysStart) ?? todaysStart
        return finishedAt < lastStart
    }
}
