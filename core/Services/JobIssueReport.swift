import Foundation

// MARK: - Job issue reporting (TASK-638)

/// Curated, PUBLIC context for a "report an issue with this job" GitHub issue. Deliberately excludes
/// the résumé, personal info, private notes, and fit analysis — it carries only the public posting and
/// how the app parsed it, so a maintainer can reproduce a parsing/availability bug from the issue alone.
public struct JobIssueReportInput: Sendable {
    public let jobNumber: Int?
    public let sourceURL: String
    public let company: String?
    public let title: String?
    public let location: String?
    public let remoteType: String?
    public let salary: String?
    public let employmentType: String?
    public let seniority: String?
    public let status: String
    public let extractionModel: String?
    public let extractionStatus: String
    public let descriptionCharCount: Int
    /// Short prefix of the cleaned-description hash — lets a maintainer tell captures apart without
    /// exposing the (potentially large / less-public) description text.
    public let descriptionHashPrefix: String?
    public let appVersion: String
    public let osVersion: String

    public init(
        jobNumber: Int?, sourceURL: String, company: String?, title: String?, location: String?,
        remoteType: String?, salary: String?, employmentType: String?, seniority: String?, status: String,
        extractionModel: String?, extractionStatus: String, descriptionCharCount: Int,
        descriptionHashPrefix: String?, appVersion: String, osVersion: String
    ) {
        self.jobNumber = jobNumber
        self.sourceURL = sourceURL
        self.company = company
        self.title = title
        self.location = location
        self.remoteType = remoteType
        self.salary = salary
        self.employmentType = employmentType
        self.seniority = seniority
        self.status = status
        self.extractionModel = extractionModel
        self.extractionStatus = extractionStatus
        self.descriptionCharCount = descriptionCharCount
        self.descriptionHashPrefix = descriptionHashPrefix
        self.appVersion = appVersion
        self.osVersion = osVersion
    }
}

public struct JobIssueReport: Sendable, Equatable {
    public let title: String
    public let body: String
}

public enum JobIssueReportBuilder {
    /// A stable marker so job-issue reports are findable even if the label is missing.
    public static let marker = "<!-- jobhunt:job-report -->"

    /// Builds the GitHub issue title + Markdown body: a "What's wrong?" prompt for the user plus an
    /// auto-filled public context block a maintainer can act on.
    public static func build(_ input: JobIssueReportInput) -> JobIssueReport {
        let title = truncate("Job issue: \(orUnknown(input.company)) — \(orUnknown(input.title))", limit: 120)

        var body = "\(marker)\n\n"
        body += "## What's wrong?\n\n"
        body += "_Describe the problem with this job's data — replace this line._\n\n"
        body += "## Job context (auto-filled — please keep)\n\n"
        body += line("Job URL", input.sourceURL.isEmpty ? "(none)" : input.sourceURL)
        body += line("Company (parsed)", orUnknown(input.company))
        body += line("Title (parsed)", orUnknown(input.title))
        body += line("Location (parsed)", orUnknown(input.location))
        body += line("Remote (parsed)", orUnknown(input.remoteType))
        body += line("Salary (parsed)", orUnknown(input.salary))
        body += line("Employment (parsed)", orUnknown(input.employmentType))
        body += line("Seniority (parsed)", orUnknown(input.seniority))
        body += line("Workflow status", input.status)
        body += line("Extraction", "\(orUnknown(input.extractionModel)) (\(input.extractionStatus))")
        let hashSuffix = input.descriptionHashPrefix.map { " · hash \($0)" } ?? ""
        body += line("Description", "\(input.descriptionCharCount) chars\(hashSuffix)")
        body += line("App", "\(input.appVersion) · macOS \(input.osVersion)")
        body += line("Ref", "job #\(input.jobNumber.map(String.init) ?? "?")")
        return JobIssueReport(title: title, body: body)
    }

    private static func orUnknown(_ value: String?) -> String {
        let trimmed = (value ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "(unknown)" : trimmed
    }

    private static func line(_ label: String, _ value: String) -> String {
        "- \(label): \(value)\n"
    }

    private static func truncate(_ value: String, limit: Int) -> String {
        value.count <= limit ? value : String(value.prefix(limit - 1)) + "…"
    }
}

/// Opens a prefilled GitHub "new issue" for the jobhunt repo. Prefill via `?body=` is length-limited, so
/// callers always copy the full report to the clipboard first and fall back to `blankIssueURL` when the
/// prefilled URL exceeds the budget (TASK-638).
public enum GitHubIssueReporter {
    public static let repoSlug = "brooksc/jobhunt"
    public static let reportLabel = "job-report"
    /// Conservative ceiling on the whole prefilled URL — GitHub accepts long URLs, but keep margin.
    static let maxURLChars = 8000

    public static func newIssueURL(report: JobIssueReport, labels: [String] = [reportLabel]) -> URL? {
        var components = URLComponents(string: "https://github.com/\(repoSlug)/issues/new")
        components?.queryItems = [
            URLQueryItem(name: "title", value: report.title),
            URLQueryItem(name: "labels", value: labels.joined(separator: ",")),
            URLQueryItem(name: "body", value: report.body)
        ]
        guard let url = components?.url, url.absoluteString.count <= maxURLChars else { return nil }
        return url
    }

    public static var blankIssueURL: URL {
        URL(string: "https://github.com/\(repoSlug)/issues/new?labels=\(reportLabel)")
            ?? URL(fileURLWithPath: "/") // unreachable: the literal above is always a valid URL
    }
}
