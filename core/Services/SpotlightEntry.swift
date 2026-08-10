import Foundation

/// What a job looks like in the Spotlight index (TASK-590).
///
/// The attribute values are composed here, in Core, rather than inline in the CoreSpotlight adapter,
/// so what gets indexed is unit-tested. The adapter's job is only to hand these to
/// `CSSearchableItem` — a thin layer over a framework we can't exercise in tests anyway.
public struct SpotlightEntry: Sendable, Equatable {
    /// Stable across re-indexing, and derived from the job *number* rather than the UUID: the number
    /// is what the deep link uses and what the user sees.
    public let uniqueIdentifier: String
    public let title: String
    public let contentDescription: String
    public let keywords: [String]
    /// `jobhunt://jobs/N` — the same deep link the notifications use, so clicking a Spotlight result
    /// lands in the same place (#2).
    public let deepLink: String

    /// Prefix for every item this app owns, so "clear the index" can be exact rather than a
    /// blanket wipe of the app's domain.
    public static let identifierPrefix = "jobhunt-job-"

    public static func identifier(jobNumber: Int) -> String {
        "\(identifierPrefix)\(jobNumber)"
    }

    /// Builds the entry, or nil when the job can't be linked or named.
    ///
    /// A job with no number has no deep link, so a Spotlight hit would open the app and land
    /// nowhere — worse than not appearing. A job with no title and no company has nothing to match
    /// on and would show as a blank row.
    public static func make(
        jobNumber: Int?,
        title: String?,
        company: String?,
        location: String?,
        salary: String?,
        status: String,
        skills: [String]
    ) -> SpotlightEntry? {
        guard let jobNumber else { return nil }
        let cleanTitle = clean(title)
        let cleanCompany = clean(company)
        guard cleanTitle != nil || cleanCompany != nil else { return nil }

        let displayTitle: String = if let cleanTitle, let cleanCompany {
            "\(cleanTitle) at \(cleanCompany)"
        } else {
            cleanTitle ?? cleanCompany ?? ""
        }

        // Status last: it's the least useful thing for finding a job and the most useful for
        // recognising the right one once several match.
        let description = [clean(location), clean(salary), status]
            .compactMap(\.self)
            .joined(separator: " · ")

        // The company is a keyword as well as part of the title. Spotlight matches titles, but a
        // user searching "Acme" should hit every Acme job whether or not the title reads well.
        var keywords = skills.compactMap(clean)
        if let cleanCompany { keywords.append(cleanCompany) }

        return SpotlightEntry(
            uniqueIdentifier: identifier(jobNumber: jobNumber),
            title: displayTitle,
            contentDescription: description,
            keywords: keywords,
            deepLink: "jobhunt://jobs/\(jobNumber)"
        )
    }

    private static func clean(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else { return nil }
        return trimmed
    }
}
