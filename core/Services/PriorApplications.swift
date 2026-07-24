import Foundation

// MARK: - Prior applications guard (TASK-615)

/// An informational safeguard: when viewing an Interested job, surface other jobs at the same normalized
/// company the user has already applied to — so they don't apply twice. Never blocks; pure + testable.
public enum PriorApplications {
    /// Pure projection of a job for the prior-application check.
    public struct JobInput: Sendable {
        public let jobID: String
        public let jobNumber: Int?
        public let company: String?
        public let title: String?
        public let currentStatus: String
        public let appliedAt: Date?

        public init(
            jobID: String, jobNumber: Int?, company: String?, title: String?,
            currentStatus: String, appliedAt: Date?
        ) {
            self.jobID = jobID
            self.jobNumber = jobNumber
            self.company = company
            self.title = title
            self.currentStatus = currentStatus
            self.appliedAt = appliedAt
        }
    }

    public struct Match: Sendable, Equatable, Identifiable {
        public let jobID: String
        public let jobNumber: Int?
        public let title: String?
        public let currentStatus: String
        public let appliedAt: Date?
        /// True when the title strongly matches the viewed job's — "Possible repeat application".
        public let likelyRepeat: Bool
        public var id: String {
            jobID
        }
    }

    /// Statuses that (with `appliedAt` absent) still imply a past application, for legacy rows (AC).
    static let appliedImplyingStatuses: Set<String> = ["applied", "interview", "offer", "rejected"]

    static func hasApplied(_ job: JobInput) -> Bool {
        job.appliedAt != nil || appliedImplyingStatuses.contains(job.currentStatus)
    }

    /// Other jobs at the same normalized company that have an applied history, newest application first.
    /// Empty company / no match → empty. Excludes the viewed job itself.
    public static func priorApplications(for job: JobInput, among others: [JobInput]) -> [Match] {
        let company = normalizedCompany(job.company)
        guard !company.isEmpty else { return [] }
        return others
            .filter { $0.jobID != job.jobID && hasApplied($0) && normalizedCompany($0.company) == company }
            .map {
                Match(
                    jobID: $0.jobID, jobNumber: $0.jobNumber, title: $0.title, currentStatus: $0.currentStatus,
                    appliedAt: $0.appliedAt, likelyRepeat: titlesLikelyMatch(job.title, $0.title)
                )
            }
            .sorted { ($0.appliedAt ?? .distantPast) > ($1.appliedAt ?? .distantPast) }
    }

    /// Company tokens with no identity signal (legal suffixes, generic noise) — dropped before matching
    /// so "Acme" and "Acme, Inc." are treated as the same employer.
    static let companyStopWords: Set<String> = [
        "the", "inc", "incorporated", "corp", "corporation", "co", "company", "ltd", "limited",
        "llc", "llp", "lp", "plc", "gmbh", "group", "holdings", "holding"
    ]

    /// Conservative company normalization: lowercased, punctuation stripped, legal suffixes/noise dropped.
    /// Returns "" for empty/generic-only names so they never match (avoids false "already applied").
    public static func normalizedCompany(_ name: String?) -> String {
        let tokens = (name ?? "")
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty && $0.count > 1 && !companyStopWords.contains($0) }
        return tokens.joined(separator: " ")
    }

    /// Titles "likely match" when their normalized meaningful words are equal or one is a subset of the
    /// other (e.g. "Staff TPM" ⊆ "Staff TPM, Platform") — a stronger "possible repeat" signal.
    static func titlesLikelyMatch(_ lhs: String?, _ rhs: String?) -> Bool {
        let left = titleTokens(lhs)
        let right = titleTokens(rhs)
        guard !left.isEmpty, !right.isEmpty else { return false }
        return left == right || left.isSubset(of: right) || right.isSubset(of: left)
    }

    private static func titleTokens(_ title: String?) -> Set<String> {
        Set((title ?? "")
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count > 1 })
    }
}
