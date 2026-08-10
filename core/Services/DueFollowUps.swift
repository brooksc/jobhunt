import Foundation

/// Which follow-ups are due enough to interrupt someone about (TASK-589).
///
/// A follow-up only surfaced if the user happened to open Needs Action, which defeats the point of
/// having a due date. This decides *what* to say; delivery stays in the app layer.
public enum DueFollowUps {
    /// A due follow-up, flattened so it can cross the actor boundary (`JobAction` can't).
    public struct Item: Sendable, Equatable, Identifiable {
        public let id: String
        public let jobNumber: Int?
        public let title: String
        public let company: String?
        public let note: String

        public init(id: String, jobNumber: Int?, title: String, company: String?, note: String) {
            self.id = id
            self.jobNumber = jobNumber
            self.title = title
            self.company = company
            self.note = note
        }
    }

    /// What to post, if anything.
    public struct Notification: Sendable, Equatable {
        public let title: String
        public let body: String
        /// Deep link for the click, when a single job is unambiguous.
        public let jobNumber: Int?
        /// Every id covered, so the caller can mark them notified — including the ones folded into a
        /// summary. Marking only the named ones would re-notify the rest forever.
        public let coveredIDs: [String]
    }

    /// Above this, one summary instead of a stack of banners. Five is where a notification centre
    /// full of near-identical rows stops being information and starts being noise.
    public static let individualLimit = 5

    /// Whether a follow-up is currently due: not completed, its due date passed, and not snoozed
    /// into the future.
    ///
    /// A snooze *into the past* is not a snooze any more — it's an expired one, and the follow-up is
    /// due again. Reading a stale `snoozedUntil` as "still snoozed" would silence it permanently.
    public static func isDue(
        dueDate: Date, completedAt: Date?, snoozedUntil: Date?, now: Date = Date()
    ) -> Bool {
        guard completedAt == nil else { return false }
        guard dueDate <= now else { return false }
        if let snoozedUntil, snoozedUntil > now { return false }
        return true
    }

    /// Builds the notification for this cycle, or nil when there's nothing new to say.
    ///
    /// - Parameter alreadyNotified: ids notified earlier in this app session. Tracked in memory by
    ///   the caller: re-notifying once per launch is a reasonable reminder, whereas a persisted flag
    ///   would need a migration and a rule for when to clear it.
    public static func notification(
        for items: [Item],
        alreadyNotified: Set<String>
    ) -> Notification? {
        let fresh = items.filter { !alreadyNotified.contains($0.id) }
        guard !fresh.isEmpty else { return nil }

        if fresh.count == 1, let item = fresh[0] as Item? {
            return Notification(
                title: "Follow-up due",
                body: describe(item),
                jobNumber: item.jobNumber,
                coveredIDs: [item.id]
            )
        }

        if fresh.count <= individualLimit {
            return Notification(
                title: "\(fresh.count) follow-ups due",
                body: fresh.map(describe).joined(separator: "\n"),
                // No single job to open — the click should land on the list, not on an arbitrary one.
                jobNumber: nil,
                coveredIDs: fresh.map(\.id)
            )
        }

        return Notification(
            title: "\(fresh.count) follow-ups due",
            body: "Open Needs Action to see them all.",
            jobNumber: nil,
            coveredIDs: fresh.map(\.id)
        )
    }

    private static func describe(_ item: Item) -> String {
        let role = [item.title, item.company].compactMap { $0?.isEmpty == false ? $0 : nil }
            .joined(separator: " at ")
        let trimmedNote = item.note.trimmingCharacters(in: .whitespacesAndNewlines)
        if role.isEmpty { return trimmedNote.isEmpty ? "Follow up" : trimmedNote }
        return trimmedNote.isEmpty ? role : "\(role) — \(trimmedNote)"
    }
}
