import AppKit
import JobhuntCore
import SwiftUI

/// "Report an issue" for the displayed job (TASK-638): assembles a public, curated context report,
/// copies it to the clipboard, and opens a prefilled GitHub issue (falling back to a blank issue when
/// the prefilled URL is too long). Maintainers track these via the `job-report` label.
struct JobIssueButton: View {
    let job: Job

    @Environment(AppServices.self) private var appServices

    var body: some View {
        Button { report() } label: {
            Label("Report an issue", systemImage: "exclamationmark.bubble")
                .font(.caption2.weight(.semibold))
        }
        .buttonStyle(.borderless)
        .help("Report a problem with this job's parsed data on GitHub")
    }

    private func report() {
        let report = JobIssueReportBuilder.build(makeInput())
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(report.body, forType: .string)
        if let url = GitHubIssueReporter.newIssueURL(report: report) {
            NSWorkspace.shared.open(url)
            appServices.toastStore.show("Opening GitHub — the report is prefilled (and copied to your clipboard)")
        } else {
            NSWorkspace.shared.open(GitHubIssueReporter.blankIssueURL)
            appServices.toastStore.show("Report copied to your clipboard — paste it into the new GitHub issue")
        }
    }

    private func makeInput() -> JobIssueReportInput {
        JobIssueReportInput(
            jobNumber: job.jobNumber,
            sourceURL: JobURLPolicy.sourceURL(job: job) ?? "",
            company: job.company,
            title: job.title,
            location: job.location,
            remoteType: job.remoteType?.rawValue,
            salary: salaryString(job),
            employmentType: job.employmentType,
            seniority: job.seniority,
            status: job.status.rawValue,
            extractionModel: job.extractionModel,
            extractionStatus: job.extractionStatus.rawValue,
            descriptionCharCount: job.capture?.cleanedDescription?.count ?? 0,
            descriptionHashPrefix: job.capture?.cleanedHash.map { String($0.prefix(12)) },
            appVersion: appVersionString,
            osVersion: ProcessInfo.processInfo.operatingSystemVersionString
        )
    }

    private var appVersionString: String {
        let short = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
        return "\(short) (\(build))"
    }

    private func salaryString(_ job: Job) -> String? {
        guard let min = job.salaryMin else { return nil }
        let currency = job.salaryCurrency ?? ""
        if let max = job.salaryMax { return "\(currency)\(min)–\(max)" }
        return "\(currency)\(min)+"
    }
}
