import Foundation

/// Converting a chosen snooze date into the day count the snooze path already speaks (TASK-502).
///
/// The fixed intervals (3d / 1w / 2w / 1mo) cover the common cases but not the one that actually
/// prompts a snooze — "they said they'd get back to me after the 14th".
public enum SnoozeDefaults {
    /// Where the picker opens. A week out, not today: today is the one date that is never the answer
    /// to "when should this come back?".
    public static func defaultCustomDate(from now: Date = Date(), calendar: Calendar = .current) -> Date {
        calendar.date(byAdding: .day, value: 7, to: now) ?? now
    }

    /// Whole days from today to `date`, floored at 1.
    ///
    /// Compared by *calendar day*, not elapsed hours: picking tomorrow morning while it's currently
    /// evening is 0.6 days of elapsed time and would truncate to today — snoozing something to right
    /// now, which is what the user was trying to avoid.
    ///
    /// A past date floors to 1 rather than erroring. The picker can offer past dates, and the least
    /// surprising reading of "snooze until yesterday" is tomorrow, not a rejected action.
    public static func days(until date: Date, from now: Date = Date(), calendar: Calendar = .current) -> Int {
        let start = calendar.startOfDay(for: now)
        let end = calendar.startOfDay(for: date)
        let difference = calendar.dateComponents([.day], from: start, to: end).day ?? 1
        return max(difference, 1)
    }
}
