import Foundation

/// Which tracked sites are due for another sweep, and what to say about them (TASK-503).
///
/// The Sites screen is a scan log: you bookmark a careers page, work through its listings, mark it
/// done, and want telling when it's worth another look. The marking and the interval already
/// existed — `Site.intervalDays`, `lastReviewedAt`, `nextReviewAt`, `markReviewed` — but nothing
/// ever told you. A due date that only surfaces if you happen to open the screen is the same
/// non-reminder that motivated the follow-up notifier, and for the same reason: the whole point is
/// not to have to remember.
///
/// This decides *what* to say; delivery stays in the app layer.
public enum DueSiteReviews {
    /// A site due for review, flattened so it can cross the actor boundary (`Site` can't).
    public struct Item: Sendable, Equatable, Identifiable {
        public let id: String
        public let name: String
        public let daysOverdue: Int

        public init(id: String, name: String, daysOverdue: Int) {
            self.id = id
            self.name = name
            self.daysOverdue = daysOverdue
        }
    }

    public struct Notification: Sendable, Equatable {
        public let title: String
        public let body: String
        /// Every id covered, so the caller can mark them notified — including ones folded into a
        /// summary. Marking only the named ones would re-notify the rest forever.
        public let coveredIDs: [String]

        /// Stable across launches: the same set of sites keeps the same id, so a repeat replaces
        /// rather than stacks. FNV-1a rather than `hashValue`, which Swift seeds per process.
        public var notificationID: String {
            var hash: UInt64 = 0xCBF2_9CE4_8422_2325
            for byte in coveredIDs.sorted().joined(separator: "\u{1}").utf8 {
                hash = (hash ^ UInt64(byte)) &* 0x0000_0100_0000_01B3
            }
            return "site-reviews-\(String(hash, radix: 16))"
        }
    }

    /// Above this, one summary instead of a stack of names.
    public static let individualLimit = 3

    /// Whether a site is due: it has a next-review date and that date has passed.
    ///
    /// A site with no `nextReviewAt` has never been reviewed and has no schedule to be late against
    /// — it belongs in the screen's own "not yet reviewed" bucket, not in an interruption.
    public static func isDue(nextReviewAt: Date?, now: Date = Date()) -> Bool {
        guard let nextReviewAt else { return false }
        return nextReviewAt <= now
    }

    public static func daysOverdue(nextReviewAt: Date, now: Date = Date(), calendar: Calendar = .current) -> Int {
        let days = calendar.dateComponents(
            [.day], from: calendar.startOfDay(for: nextReviewAt), to: calendar.startOfDay(for: now)
        ).day ?? 0
        return max(days, 0)
    }

    /// What to post, or nil when there's nothing new to say.
    ///
    /// - Parameter alreadyNotified: ids notified earlier in this session. Held in memory by the
    ///   caller: re-reminding once per launch is reasonable for a reminder, and a persisted flag
    ///   would need a migration plus a rule for clearing it.
    public static func notification(
        for items: [Item],
        alreadyNotified: Set<String>
    ) -> Notification? {
        let fresh = items.filter { !alreadyNotified.contains($0.id) }
        guard !fresh.isEmpty else { return nil }

        if fresh.count == 1, let site = fresh.first {
            return Notification(
                title: "Time to check \(site.name)",
                body: describe(site),
                coveredIDs: [site.id]
            )
        }
        if fresh.count <= individualLimit {
            return Notification(
                title: "\(fresh.count) sites due for a look",
                body: fresh.map(\.name).joined(separator: ", "),
                coveredIDs: fresh.map(\.id)
            )
        }
        return Notification(
            title: "\(fresh.count) sites due for a look",
            body: "Open Sites to see which.",
            coveredIDs: fresh.map(\.id)
        )
    }

    private static func describe(_ site: Item) -> String {
        switch site.daysOverdue {
        case 0: "Due today — you last swept it a while ago."
        case 1: "Due since yesterday."
        default: "Due for \(site.daysOverdue) days."
        }
    }
}
