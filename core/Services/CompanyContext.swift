import Foundation

// MARK: - CompanyContext

/// What else is going on at the company whose job you're reading: other roles still open in your
/// pipeline, and whether they've rejected you before.
///
/// Sits alongside `PriorApplications` (which answers "have I already applied here?"). This answers the
/// different question of "is this the *best* role to go for here?", which is why matches carry their
/// fit score and are ranked by it — a bare list of titles is navigation, not a decision aid.
public enum CompanyContext {
    /// Statuses that still represent a live candidate worth comparing against.
    public static let openStatuses: Set<JobStatus> = [.new, .pursuing]

    public struct Role: Sendable, Equatable, Identifiable {
        public let jobID: String
        public let jobNumber: Int?
        public let title: String
        public let status: JobStatus
        /// Nil when the job was never fit-scored — shown as "—" rather than implying a zero.
        public let fitScore: Int?
        public var id: String {
            jobID
        }

        public init(jobID: String, jobNumber: Int?, title: String, status: JobStatus, fitScore: Int?) {
            self.jobID = jobID
            self.jobNumber = jobNumber
            self.title = title
            self.status = status
            self.fitScore = fitScore
        }
    }

    public struct Result: Sendable, Equatable {
        /// Other still-open roles at the company, best fit first.
        public let openRoles: [Role]
        /// Roles at this company that ended in rejection — informational only.
        public let rejectedRoles: [Role]

        public var isEmpty: Bool {
            openRoles.isEmpty && rejectedRoles.isEmpty
        }

        /// The highest fit score among the alternatives, when any were scored.
        public var bestFit: Int? {
            openRoles.compactMap(\.fitScore).max()
        }

        public init(openRoles: [Role], rejectedRoles: [Role]) {
            self.openRoles = openRoles
            self.rejectedRoles = rejectedRoles
        }
    }

    /// Normalized company key. Case and surrounding whitespace vary in extracted data (the store holds
    /// both "Twilio" and "twilio"), so those must group. Deliberately conservative otherwise — no
    /// suffix stripping — because wrongly merging two different companies is more confusing than
    /// missing a match.
    public static func companyKey(_ company: String?) -> String {
        (company ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    /// Build the context for `viewed` from the rest of the library.
    ///
    /// The viewed job is always excluded. Rejections are surfaced regardless of the viewed job's own
    /// status — a past rejection is context you want whenever you're weighing this company — while the
    /// open-role comparison naturally empties out once nothing else is live.
    public static func build(viewed: Role, company: String?, among others: [(role: Role, company: String?)])
        -> Result {
        let key = companyKey(company)
        guard !key.isEmpty else { return Result(openRoles: [], rejectedRoles: []) }

        let sameCompany = others
            .filter { companyKey($0.company) == key && $0.role.jobID != viewed.jobID }
            .map(\.role)

        let open = sameCompany
            .filter { openStatuses.contains($0.status) }
            // Best fit first — the whole point is choosing. Unscored roles sort last rather than as 0,
            // so a never-scored job isn't presented as a bad one.
            .sorted { lhs, rhs in
                switch (lhs.fitScore, rhs.fitScore) {
                case let (l?, r?): l == r ? lhs.title < rhs.title : l > r
                case (nil, _?): false
                case (_?, nil): true
                case (nil, nil): lhs.title < rhs.title
                }
            }

        let rejected = sameCompany
            .filter { $0.status == .rejected }
            .sorted { $0.title < $1.title }

        return Result(openRoles: open, rejectedRoles: rejected)
    }
}
