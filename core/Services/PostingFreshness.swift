import Foundation

/// How fresh a posting is, and how much to trust that answer (TASK-633).
///
/// The capture date says when *we* saw the posting, which for one found weeks after it went up says
/// nothing about the posting itself. The ATS knows when it was first published and last changed, so
/// where that's available the label is authoritative — and where it isn't, the label has to admit
/// it's guessing rather than quietly present a capture date as a posting date.
public struct PostingFreshness: Equatable, Sendable {
    public enum Confidence: Sendable, Equatable {
        /// From the employer's ATS.
        case authoritative
        /// Derived from when we captured it — a lower bound on the posting's age, never an upper one.
        case captureDate
    }

    public enum Level: Sendable, Equatable {
        case fresh
        case recent
        case aging
        case stale
    }

    public let label: String
    public let level: Level
    public let confidence: Confidence
    /// Set when the posting was published well before its last update — the shape of a repost or a
    /// long-running requisition, and a reason to wonder how active the search really is.
    public let isRepost: Bool

    /// Days after which a posting reads as stale. Six weeks is where the task's own example sits,
    /// and it's roughly the point at which a still-open requisition is more likely dormant than hot.
    public static let staleDays = 42
    public static let agingDays = 21
    public static let freshDays = 7

    /// A posting first published well before its last update is being maintained rather than newly
    /// opened. Two weeks avoids flagging the ordinary edit-a-typo-next-day case.
    public static let repostGapDays = 14

    public static func make(
        firstPublished: Date?,
        atsUpdated: Date?,
        capturedAt: Date?,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> PostingFreshness? {
        // Prefer first-published: "posted" is the question being asked. `updated_at` moves whenever
        // the employer edits a typo, which would make an ancient requisition look new.
        let authoritative = firstPublished ?? atsUpdated
        guard let reference = authoritative ?? capturedAt else { return nil }

        let days = max(dayCount(from: reference, to: now, calendar: calendar), 0)
        let level = level(forDays: days)
        let confidence: Confidence = authoritative == nil ? .captureDate : .authoritative

        let repost: Bool = if let firstPublished, let atsUpdated {
            dayCount(from: firstPublished, to: atsUpdated, calendar: calendar) >= repostGapDays
        } else {
            false
        }

        return PostingFreshness(
            label: label(days: days, confidence: confidence, isRepost: repost),
            level: level,
            confidence: confidence,
            isRepost: repost
        )
    }

    private static func level(forDays days: Int) -> Level {
        switch days {
        case ..<freshDays: .fresh
        case ..<agingDays: .recent
        case ..<staleDays: .aging
        default: .stale
        }
    }

    private static func label(days: Int, confidence: Confidence, isRepost: Bool) -> String {
        let age = agePhrase(days)
        // "Captured" rather than "Posted" when that's all we know. Presenting our capture date as a
        // posting date would be a quiet lie in the one direction that matters — it always makes a
        // posting look newer than it is.
        let verb = confidence == .authoritative ? "Posted" : "Captured"
        return isRepost ? "\(verb) \(age) · updated since" : "\(verb) \(age)"
    }

    private static func agePhrase(_ days: Int) -> String {
        switch days {
        case 0: "today"
        case 1: "yesterday"
        case ..<14: "\(days) days ago"
        case ..<60: "\(days / 7) weeks ago"
        default: "\(days / 30) months ago"
        }
    }

    private static func dayCount(from: Date, to: Date, calendar: Calendar) -> Int {
        calendar.dateComponents(
            [.day], from: calendar.startOfDay(for: from), to: calendar.startOfDay(for: to)
        ).day ?? 0
    }
}
