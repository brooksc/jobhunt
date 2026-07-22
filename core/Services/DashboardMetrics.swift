import Foundation

// MARK: - DashboardMetrics

// Pure helpers — no SwiftData, no side effects. Ported from counts.js buildDailyActivity.
// Lives in JobhuntCore (not the app module) so the date-window logic is unit-testable across a
// simulated day boundary (TASK-583).

public enum DashboardMetrics {
    /// Group captures by calendar day, fill zeros for missing days in the last 30 days.
    /// Returns array sorted oldest → newest (ascending), suitable for Charts.
    ///
    /// `now` is an explicit input (not `Date()`) so the 30-day window advances when the calendar day
    /// changes — the caller passes a day token that ticks at local midnight — and so the window is
    /// testable across a day boundary (TASK-583).
    public static func buildDailyActivity(
        captures: [(capturedAt: Date, id: String)],
        now: Date = Date()
    ) -> [(day: Date, count: Int)] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now)
        guard let thirtyDaysAgo = calendar.date(byAdding: .day, value: -29, to: today) else { return [] }

        // Count captures per calendar day
        var countByDay: [Date: Int] = [:]
        for capture in captures {
            let day = calendar.startOfDay(for: capture.capturedAt)
            if day >= thirtyDaysAgo {
                countByDay[day, default: 0] += 1
            }
        }

        // Fill all 30 days, including zeros
        var result: [(day: Date, count: Int)] = []
        var cursor = thirtyDaysAgo
        while cursor <= today {
            result.append((day: cursor, count: countByDay[cursor] ?? 0))
            guard let next = calendar.date(byAdding: .day, value: 1, to: cursor) else { break }
            cursor = next
        }
        return result
    }

    // MARK: - Daily recap (TASK-623)

    /// Minimal Sendable projection of a `JobEvent` for the pure recap builder.
    public struct RecapEvent: Sendable {
        public let eventType: String
        public let note: String?
        public let occurredAt: Date
        public init(eventType: String, note: String?, occurredAt: Date) {
            self.eventType = eventType
            self.note = note
            self.occurredAt = occurredAt
        }
    }

    /// Aggregate a single day's *user-driven* activity from the authoritative event log + completed
    /// follow-ups. Derived from immutable events (not current job status) so a past day's recap stays
    /// correct even after a job later changes status. Background extraction / AI / duplicate-scan events
    /// are deliberately excluded — only meaningful human actions are counted (TASK-623).
    public static func buildDailyRecap(
        events: [RecapEvent],
        followUpCompletions: [Date],
        day: Date,
        calendar: Calendar = .current
    ) -> DailyRecap {
        var recap = DailyRecap()
        for event in events where calendar.isDate(event.occurredAt, inSameDayAs: day) {
            switch event.eventType {
            case "capture", "captured", "recapture", "recaptured":
                recap.captured += 1
            case "duplicate_decided":
                recap.duplicatesResolved += 1
            case "note", "note_added":
                recap.notesAdded += 1
            case "status", "status_changed":
                switch statusTarget(fromNote: event.note) {
                case "pursuing": recap.movedToInterested += 1
                case "applied": recap.applied += 1
                case "interview": recap.interviews += 1
                case "offer": recap.offers += 1
                case "passed", "archived", "rejected", "closed", "expired": recap.triaged += 1
                default: break // new / duplicate / unknown target — not a meaningful milestone
                }
            default:
                break // extraction, extraction_queued, duplicate_detected, availability, source_opened
            }
        }
        recap.followUpsCompleted = followUpCompletions.filter { calendar.isDate($0, inSameDayAs: day) }.count
        return recap
    }

    /// The target status of a status-change event — from the current "Status changed from X to Y" note
    /// or a legacy single-token note — mapped to the current vocabulary. Nil if unrecognized.
    static func statusTarget(fromNote note: String?) -> String? {
        guard let raw = note?.lowercased().trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else {
            return nil
        }
        let token: String = if let range = raw.range(of: " to ", options: .backwards) {
            String(raw[range.upperBound...]).trimmingCharacters(in: .whitespaces)
        } else {
            raw
        }
        // Map legacy Electron-era status words onto the current JobStatus vocabulary.
        let legacy = ["saved": "pursuing", "ignored": "passed", "not_available": "expired"]
        return legacy[token] ?? token
    }
}

/// A humane end-of-day summary of the meaningful, user-driven work done on a given day (TASK-623).
public struct DailyRecap: Sendable, Equatable {
    public var captured = 0            // jobs found / captured
    public var movedToInterested = 0  // status → pursuing
    public var applied = 0            // status → applied
    public var interviews = 0         // status → interview
    public var offers = 0             // status → offer
    public var triaged = 0            // status → passed/archived/rejected/closed/expired (cleared out)
    public var duplicatesResolved = 0 // a duplicate pair resolved
    public var notesAdded = 0         // a note written
    public var followUpsCompleted = 0 // a follow-up action completed

    public init() {}

    /// Count of meaningful actions — drives the momentum line and the empty state.
    public var total: Int {
        captured + movedToInterested + applied + interviews + offers
            + triaged + duplicatesResolved + notesAdded + followUpsCompleted
    }

    public var hasActivity: Bool { total > 0 }
}
