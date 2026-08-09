import Foundation

/// Completions for the Jobs search field, drawn from the user's own captured jobs.
///
/// The structured tokens (status, salary, fit) suggest values the app knows about; freeform text
/// suggested nothing, so finding every job at a company meant remembering exactly how that company
/// spells itself.
public enum JobTextSuggestions {
    /// What the completion will match on — the search field's freetext matcher covers both, but the
    /// row should say which one it came from.
    public enum Kind: Sendable, Equatable {
        case company
        case title
    }

    public struct Suggestion: Sendable, Equatable, Identifiable {
        public let text: String
        public let kind: Kind
        public var id: String {
            "\(kind)-\(text)"
        }
    }

    /// Below this a prefix matches most of the corpus, and the dropdown becomes noise that hides the
    /// structured token suggestions sharing the same list.
    public static let minimumPrefixLength = 2

    /// - Parameters:
    ///   - limit: per kind, not total — companies shouldn't be able to crowd titles out.
    ///
    /// Matches a prefix of the whole value *or* of any word in it, so "systems" finds "Bright
    /// Systems". Whole-string-only prefix matching requires knowing how the name starts, which is
    /// the thing the user is trying not to have to remember.
    public static func suggest(
        prefix: String,
        companies: some Sequence<String>,
        titles: some Sequence<String>,
        limit: Int = 5
    ) -> [Suggestion] {
        let needle = prefix.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard needle.count >= minimumPrefixLength else { return [] }

        func pick(_ values: some Sequence<String>, _ kind: Kind) -> [Suggestion] {
            let matches = values
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty && hasPrefix(needle, in: $0) }
            // Case-insensitive dedup, but the FIRST spelling seen is kept: inserting a lowercased
            // company name into the search field would look like a typo of the user's own data.
            var seen = Set<String>()
            let unique = matches.filter { seen.insert($0.lowercased()).inserted }
            return unique
                .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
                .prefix(limit)
                .map { Suggestion(text: $0, kind: kind) }
        }

        return pick(companies, .company) + pick(titles, .title)
    }

    private static func hasPrefix(_ needle: String, in value: String) -> Bool {
        let lowered = value.lowercased()
        if lowered.hasPrefix(needle) { return true }
        return lowered.split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .contains { $0.hasPrefix(needle) }
    }
}
