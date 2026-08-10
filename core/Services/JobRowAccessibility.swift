import Foundation

/// The one sentence VoiceOver should read for a job row (TASK-506 #2).
///
/// A row is a dozen separate views — ring, title, company, location, salary, status dot, unread dot.
/// Left alone, VoiceOver walks them one at a time, so moving down a list of jobs means hearing a
/// dozen fragments per row, several of which ("dot", "circle") mean nothing. Composed into one
/// sentence, a row is a single stop that says what it is.
///
/// Order matters: the two things you scan a list *for* — the role and how well it fits — come first,
/// and the bookkeeping follows.
public enum JobRowAccessibility {
    public static func label(
        title: String?,
        company: String?,
        location: String?,
        salary: String?,
        fitScore: Int?,
        status: String,
        isUnread: Bool
    ) -> String {
        var parts: [String] = []

        let role = clean(title) ?? "Untitled job"
        if let company = clean(company) {
            parts.append("\(role) at \(company)")
        } else {
            parts.append(role)
        }

        // The fit is why the list is sorted the way it is; an unscored job says so rather than
        // being silently absent, since "no score" and "a bad score" are different situations.
        if let fitScore {
            parts.append(FitBand.accessibilityLabel(score: fitScore))
        } else {
            parts.append(FitBand.unscoredAccessibilityLabel)
        }

        if let location = clean(location) { parts.append(location) }
        if let salary = clean(salary) { parts.append(salary) }
        parts.append(status)
        // Last, because it's the least important thing about the row and the first thing that would
        // get in the way if it were spoken first.
        if isUnread { parts.append("Unread") }

        return parts.joined(separator: ". ")
    }

    private static func clean(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else { return nil }
        return trimmed
    }
}
