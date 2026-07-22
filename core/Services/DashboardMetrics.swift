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
}
