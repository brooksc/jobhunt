import Foundation

/// A user-authored prompt template (TASK-627).
///
/// Stored as JSON in a setting, like `ScoringFeedback` — no schema migration, and the whole list
/// round-trips as one value.
public struct PromptTemplate: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public var name: String
    public var body: String
    public var isEnabled: Bool
    /// Manual ordering in the menu. Explicit rather than array position so a reorder is a value
    /// change rather than a list rebuild.
    public var sortOrder: Int

    public init(
        id: String = UUID().uuidString,
        name: String,
        body: String,
        isEnabled: Bool = true,
        sortOrder: Int = 0
    ) {
        self.id = id
        self.name = name
        self.body = body
        self.isEnabled = isEnabled
        self.sortOrder = sortOrder
    }

    /// #14. Generous but finite: a name longer than this is unreadable in a menu, and a template
    /// longer than this is past what any provider will accept anyway.
    public static let maximumNameLength = 60
    public static let maximumBodyLength = 20000
}

/// The variables a template may reference (#3).
///
/// Namespaced `{{job.company}}` rather than bare `{{company}}`: it reads as prose, and it leaves
/// room to add `{{resume.*}}` and `{{fit.*}}` without collisions.
public enum PromptVariable: String, CaseIterable, Sendable {
    case jobCompany = "job.company"
    case jobTitle = "job.title"
    case jobLocation = "job.location"
    case jobURL = "job.url"
    case jobDescription = "job.description"
    case resumeText = "resume.text"
    case fitAnalysis = "fit.analysis"

    /// #4 — shown in the insertion menu, so nobody has to memorise token syntax.
    public var label: String {
        switch self {
        case .jobCompany: "Company"
        case .jobTitle: "Job title"
        case .jobLocation: "Location"
        case .jobURL: "Posting URL"
        case .jobDescription: "Full job description"
        case .resumeText: "Selected résumé"
        case .fitAnalysis: "Fit analysis"
        }
    }

    public var detail: String {
        switch self {
        case .jobCompany: "The employer's name"
        case .jobTitle: "The role title"
        case .jobLocation: "Where the job is based"
        case .jobURL: "Link to the original posting"
        case .jobDescription: "The cleaned posting text, in full"
        case .resumeText: "The résumé currently selected for this job"
        case .fitAnalysis: "The fit score's reasoning, when one exists"
        }
    }

    public var token: String {
        "{{\(rawValue)}}"
    }

    /// Whether the prompt is useless without it (#11). A missing company is a footnote; a missing
    /// job description means the prompt has nothing to work on.
    public var isRequiredWhenUsed: Bool {
        switch self {
        case .jobDescription, .resumeText: true
        case .jobCompany, .jobTitle, .jobLocation, .jobURL, .fitAnalysis: false
        }
    }

    /// #11 — optional values render this rather than vanishing. An empty string would leave the
    /// model reading "the role at  in " and inferring something wrong from the gap.
    public var notAvailableMarker: String {
        "[not available]"
    }
}
