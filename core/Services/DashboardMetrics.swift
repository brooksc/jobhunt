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

    /// Minimal Sendable projection of a `JobEvent` for the pure recap builder. Carries the associated
    /// job's identity so the recap can drill in to the actual jobs behind each total (TASK-623).
    public struct RecapEvent: Sendable {
        public let eventType: String
        public let note: String?
        public let occurredAt: Date
        public let jobID: String?
        public let jobNumber: Int?
        public let company: String?
        public let title: String?
        public init(
            eventType: String, note: String?, occurredAt: Date,
            jobID: String? = nil, jobNumber: Int? = nil, company: String? = nil, title: String? = nil
        ) {
            self.eventType = eventType
            self.note = note
            self.occurredAt = occurredAt
            self.jobID = jobID
            self.jobNumber = jobNumber
            self.company = company
            self.title = title
        }
    }

    /// The single categorizer mapping a raw event to a meaningful-activity category — the shared source
    /// of truth for both the counts (`buildDailyRecap`) and the drill-in detail (`buildDayActivity`), so
    /// they can never disagree. Returns nil for background / non-milestone events.
    static func category(for event: RecapEvent) -> DayActivity.Category? {
        switch event.eventType {
        case "capture", "captured", "recapture", "recaptured": .found
        case "duplicate_decided": .duplicateResolved
        case "referral": .referralRequested
        case "note", "note_added": .note
        case "status", "status_changed":
            switch statusTarget(fromNote: event.note) {
            case "pursuing": .movedToInterested
            case "applied": .applied
            case "interview": .interview
            case "offer": .offer
            case "passed", "archived", "rejected", "closed", "expired": .triaged
            default: nil // new / duplicate / unknown target — not a meaningful milestone
            }
        default: nil // extraction, extraction_queued, duplicate_detected, availability, source_opened
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
            switch category(for: event) {
            case .found: recap.captured += 1
            case .movedToInterested: recap.movedToInterested += 1
            case .applied: recap.applied += 1
            case .interview: recap.interviews += 1
            case .offer: recap.offers += 1
            case .triaged: recap.triaged += 1
            case .duplicateResolved: recap.duplicatesResolved += 1
            case .referralRequested: recap.referralsRequested += 1
            case .note: recap.notesAdded += 1
            case .followUp, .none: break // follow-ups counted separately below
            }
        }
        recap.followUpsCompleted = followUpCompletions.filter { calendar.isDate($0, inSameDayAs: day) }.count
        return recap
    }

    /// Per-day meaningful-action totals for the `days`-day window ending on `endingOn` (inclusive),
    /// oldest → newest, for the "last N days" progress strip. Zero-activity days are included so the
    /// window is a continuous timeline (TASK-623).
    public static func buildRecapWindow(
        events: [RecapEvent],
        followUpCompletions: [Date],
        days: Int,
        endingOn: Date,
        calendar: Calendar = .current
    ) -> [(day: Date, total: Int)] {
        let today = calendar.startOfDay(for: endingOn)
        var result: [(day: Date, total: Int)] = []
        for offset in stride(from: max(0, days - 1), through: 0, by: -1) {
            guard let day = calendar.date(byAdding: .day, value: -offset, to: today) else { continue }
            let recap = buildDailyRecap(
                events: events, followUpCompletions: followUpCompletions, day: day, calendar: calendar
            )
            result.append((day: day, total: recap.total))
        }
        return result
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

    /// A completed follow-up for the drill-in detail — carries the job identity so a follow-up done on
    /// a day is auditable alongside the event-driven categories (TASK-623).
    public struct FollowUpCompletion: Sendable {
        public let completedAt: Date
        public let jobID: String?
        public let jobNumber: Int?
        public let company: String?
        public let title: String?
        public init(completedAt: Date, jobID: String?, jobNumber: Int?, company: String?, title: String?) {
            self.completedAt = completedAt
            self.jobID = jobID
            self.jobNumber = jobNumber
            self.company = company
            self.title = title
        }
    }

    /// The jobs behind a single day's totals, grouped by category (newest first), so the recap is
    /// auditable — the caller shows this when the user drills into a day or a metric (TASK-623). Uses the
    /// same `category(for:)` mapping as the counts, so the detail can never disagree with the numbers.
    public static func buildDayActivity(
        events: [RecapEvent],
        followUps: [FollowUpCompletion],
        day: Date,
        calendar: Calendar = .current
    ) -> DayActivity {
        var itemsByCategory: [DayActivity.Category: [DayActivity.Item]] = [:]
        for event in events where calendar.isDate(event.occurredAt, inSameDayAs: day) {
            guard let category = category(for: event) else { continue }
            itemsByCategory[category, default: []].append(DayActivity.Item(
                jobID: event.jobID, jobNumber: event.jobNumber,
                company: event.company, title: event.title, occurredAt: event.occurredAt
            ))
        }
        for followUp in followUps where calendar.isDate(followUp.completedAt, inSameDayAs: day) {
            itemsByCategory[.followUp, default: []].append(DayActivity.Item(
                jobID: followUp.jobID, jobNumber: followUp.jobNumber,
                company: followUp.company, title: followUp.title, occurredAt: followUp.completedAt
            ))
        }
        let sections = DayActivity.Category.allCases.compactMap { category -> DayActivity.Section? in
            guard let items = itemsByCategory[category], !items.isEmpty else { return nil }
            return DayActivity.Section(category: category, items: items.sorted { $0.occurredAt > $1.occurredAt })
        }
        return DayActivity(day: calendar.startOfDay(for: day), sections: sections)
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
    public var referralsRequested = 0 // a referral outreach recorded
    public var notesAdded = 0         // a note written
    public var followUpsCompleted = 0 // a follow-up action completed

    public init() {}

    /// Count of meaningful actions — drives the momentum line and the empty state.
    public var total: Int {
        captured + movedToInterested + applied + interviews + offers
            + triaged + duplicatesResolved + referralsRequested + notesAdded + followUpsCompleted
    }

    public var hasActivity: Bool { total > 0 }
}

/// The jobs behind a single day's recap totals, grouped by category — the drill-in detail (TASK-623).
public struct DayActivity: Sendable, Equatable {
    /// A meaningful-activity category, with its display label + SF Symbol (UI applies the symbol).
    public enum Category: String, Sendable, CaseIterable {
        case found, movedToInterested, applied, interview, offer, triaged, duplicateResolved
        case referralRequested, note, followUp

        public var label: String {
            switch self {
            case .found: "Jobs found"
            case .movedToInterested: "Moved to Interested"
            case .applied: "Applications"
            case .interview: "Interviews"
            case .offer: "Offers"
            case .triaged: "Triaged / cleared"
            case .duplicateResolved: "Duplicates resolved"
            case .referralRequested: "Referrals requested"
            case .note: "Notes added"
            case .followUp: "Follow-ups done"
            }
        }

        public var symbol: String {
            switch self {
            case .found: "tray.and.arrow.down"
            case .movedToInterested: "bookmark"
            case .applied: "paperplane"
            case .interview: "person.2"
            case .offer: "star"
            case .triaged: "tray.full"
            case .duplicateResolved: "doc.on.doc"
            case .referralRequested: "person.crop.circle.badge.checkmark"
            case .note: "note.text"
            case .followUp: "checkmark.circle"
            }
        }
    }

    public struct Item: Sendable, Equatable, Identifiable {
        public let jobID: String?
        public let jobNumber: Int?
        public let company: String?
        public let title: String?
        public let occurredAt: Date
        /// Stable per-row id (job + instant); jobless rows still get a unique id.
        public var id: String { "\(jobID ?? "?")|\(occurredAt.timeIntervalSinceReferenceDate)" }
    }

    public struct Section: Sendable, Equatable, Identifiable {
        public let category: Category
        public var items: [Item]
        public var id: String { category.rawValue }
    }

    public let day: Date
    public var sections: [Section]

    public var isEmpty: Bool { sections.allSatisfy { $0.items.isEmpty } }
}
