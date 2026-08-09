import Foundation

/// Ranks a company's other open roles against the one the user is looking at (TASK-634).
///
/// A large employer's board is not a shortlist: GitLab's returned 189 open roles when this was
/// built. Showing them unranked would bury the two or three that resemble what the user is actually
/// pursuing, which is the only reason to look at the list from a job page rather than the careers
/// site.
public enum OpenRoleRelevance {
    /// Words that appear in most postings and so carry no signal about similarity. Kept short on
    /// purpose — an aggressive stoplist starts discarding the words that do distinguish roles
    /// ("staff", "platform").
    private static let ignored: Set<String> = [
        "the", "and", "for", "of", "a", "an", "to", "in", "at", "with", "or",
        "job", "role", "position", "opening", "remote", "hybrid"
    ]

    public struct Scored: Sendable, Equatable, Identifiable {
        public let role: GreenhouseJobBoard.OpenRole
        /// Shared meaningful title words. Not a probability — just an ordering.
        public let titleOverlap: Int
        public let sameLocation: Bool
        public var id: String {
            role.id
        }
    }

    /// Ranked most-similar first. `excludingURLs` drops the posting the user is already on.
    ///
    /// Ties break on title, so the order is stable between calls — a list that reshuffles on every
    /// open looks broken even when the ranking is right.
    public static func rank(
        roles: [GreenhouseJobBoard.OpenRole],
        title: String?,
        location: String?,
        excludingURLs: Set<String> = []
    ) -> [Scored] {
        let wanted = tokens(title)
        let here = normalizedLocation(location)

        return roles
            .filter { !excludingURLs.contains($0.absoluteURL) }
            .map { role in
                Scored(
                    role: role,
                    titleOverlap: wanted.isEmpty ? 0 : wanted.intersection(tokens(role.title)).count,
                    sameLocation: here != nil && normalizedLocation(role.locationName) == here
                )
            }
            .sorted { lhs, rhs in
                if lhs.titleOverlap != rhs.titleOverlap { return lhs.titleOverlap > rhs.titleOverlap }
                if lhs.sameLocation != rhs.sameLocation { return lhs.sameLocation }
                return lhs.role.title.localizedCaseInsensitiveCompare(rhs.role.title)
                    == .orderedAscending
            }
    }

    /// Whether a role resembles the one in hand closely enough to show under a "similar" filter.
    ///
    /// Two shared title words rather than one: a single shared word is usually "Engineer" or
    /// "Manager", which matches half the board.
    public static func isSimilar(_ scored: Scored) -> Bool {
        scored.titleOverlap >= 2 || (scored.titleOverlap >= 1 && scored.sameLocation)
    }

    static func tokens(_ text: String?) -> Set<String> {
        guard let text else { return [] }
        let parts = text.lowercased().split { !$0.isLetter && !$0.isNumber }
        return Set(parts.map(String.init).filter { $0.count > 1 && !ignored.contains($0) })
    }

    /// Compares on the significant half of a location string. "Remote, Italy" and "Italy" are the
    /// same place for this purpose, and exact string equality would call them different.
    static func normalizedLocation(_ text: String?) -> String? {
        guard let text else { return nil }
        let cleaned = text.lowercased()
            .replacingOccurrences(of: "remote", with: "")
            .split { !$0.isLetter && !$0.isNumber }
            .map(String.init)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        return cleaned.isEmpty ? nil : cleaned
    }
}
