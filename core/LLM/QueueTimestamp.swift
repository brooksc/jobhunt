import Foundation

/// Formats a queue timestamp for a narrow table column.
///
/// The queue showed how *long* each request took but never *when* it happened, so a row that had sat
/// there since yesterday was indistinguishable from one enqueued a minute ago — which is exactly the
/// distinction you need when the queue looks stuck.
///
/// Same-day rows show the time alone. A column wide enough for a full date on every row would spend
/// most of its width repeating today's date, and the date only carries information once the row is
/// no longer from today.
public enum QueueTimestamp {
    public static func label(
        for date: Date?,
        now: Date = Date(),
        calendar: Calendar = .current,
        locale: Locale = .current
    ) -> String {
        guard let date else { return "—" }

        let time = DateFormatter()
        time.locale = locale
        time.calendar = calendar
        time.dateStyle = .none
        time.timeStyle = .short

        if calendar.isDate(date, inSameDayAs: now) {
            return time.string(from: date)
        }

        let dated = DateFormatter()
        dated.locale = locale
        dated.calendar = calendar
        dated.dateStyle = .short
        dated.timeStyle = .short
        return dated.string(from: date)
    }
}
