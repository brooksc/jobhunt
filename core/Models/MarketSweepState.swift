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

    /// How far through the board list this sweep has got.
    ///
    /// A positional index, which is only meaningful against the exact list it was taken from — so
    /// `directoryRevision` records which list that was. Without it, a directory refresh between
    /// slices silently re-reads some boards and skips others, and a shrunken list stalls a pass
    /// that can never reach its old `boardCount`.
    public var cursor: Int
    public var boardCount: Int
    /// Fingerprint of the ordered board list this pass is walking. A mismatch on resume means the
    /// cursor is meaningless.
    ///
    /// **Optional because an initializer default is not a migration default.** A non-optional
    /// property added to a model that already has rows fails the lightweight migration outright —
    /// "missing attribute values on mandatory destination attribute" — and the store won't open at
    /// all. Nil here reads as "written before this existed", which correctly forces a restart
    /// rather than trusting a cursor whose list is unknown.
    public var directoryRevision: String?
    /// The priority set used to order this pass, JSON-encoded.
    ///
    /// Persisted rather than recomputed because it is derived from the user's library, which grows
    /// as the sweep ingests — recomputing would reorder the list mid-pass and invalidate the very
    /// cursor it is meant to keep valid.
    ///
    /// Optional for the same migration reason as `directoryRevision`.
    public var priorityJSON: String?

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
        boardCount: Int = 0,
        directoryRevision: String = "",
        priority: Set<String> = []
    ) {
        self.id = id
        self.sweepID = sweepID
        self.startedAt = startedAt
        updatedAt = startedAt
        finishedAt = nil
        cursor = 0
        self.boardCount = boardCount
        self.directoryRevision = directoryRevision
        priorityJSON = (try? JSONEncoder().encode(Array(priority).sorted()))
            .flatMap { String(data: $0, encoding: .utf8) } ?? "[]"
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

    /// The priority set this pass was ordered with, so a resume rebuilds the identical list.
    public var priority: Set<String> {
        guard let data = priorityJSON?.data(using: .utf8),
              let list = try? JSONDecoder().decode([String].self, from: data) else { return [] }
        return Set(list)
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
        // Built from date components, NOT by adding elapsed hours to midnight. `byAdding: .hour`
        // adds real time, so on a DST boundary it lands on the wrong wall clock: in
        // America/Los_Angeles a 3am start became 4am on spring-forward day and 2am on fall-back
        // day. Components ask for "3 o'clock", which is what the user chose.
        //
        // Foundation resolves the two awkward cases sensibly on its own: 2am on spring-forward day
        // doesn't exist and rolls forward, 1am on fall-back day happens twice and takes the first.
        // Neither is worth special-casing for a sweep whose start time is advisory to the hour.
        let day = calendar.dateComponents([.year, .month, .day], from: now)
        guard let todaysStart = calendar.date(from: DateComponents(
            year: day.year, month: day.month, day: day.day, hour: startHour
        )) else {
            return now.timeIntervalSince(finishedAt) >= 24 * 3600
        }
        // Day arithmetic is correct with `byAdding` — a calendar day is what's wanted here, and
        // Foundation keeps the wall-clock hour across a DST boundary when adding days.
        let lastStart = todaysStart <= now
            ? todaysStart
            : calendar.date(byAdding: .day, value: -1, to: todaysStart) ?? todaysStart
        return finishedAt < lastStart
    }
}
