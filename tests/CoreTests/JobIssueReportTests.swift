import XCTest
@testable import JobhuntCore

/// TASK-638: "report an issue with this job" → prefilled public GitHub issue.
final class JobIssueReportTests: XCTestCase {
    private func input(
        company: String? = "Acme",
        title: String? = "Staff Engineer",
        url: String = "https://acme.com/jobs/1",
        descChars: Int = 4200,
        hash: String? = "abc123def456ghi"
    ) -> JobIssueReportInput {
        JobIssueReportInput(
            jobNumber: 42, sourceURL: url, company: company, title: title, location: "Remote",
            remoteType: "remote", salary: "USD200000–260000", employmentType: "full_time", seniority: "Staff",
            status: "pursuing", extractionModel: "gemini-3.1-flash-lite", extractionStatus: "succeeded",
            descriptionCharCount: descChars, descriptionHashPrefix: hash, appVersion: "1.0.9 (202607081606)",
            osVersion: "Version 15.0"
        )
    }

    func testReportIncludesPublicContextAndMarkerAndPrompt() {
        let report = JobIssueReportBuilder.build(input())
        XCTAssertEqual(report.title, "Job issue: Acme — Staff Engineer")
        XCTAssertTrue(report.body.contains(JobIssueReportBuilder.marker), "stable marker present for tracking")
        XCTAssertTrue(report.body.contains("## What's wrong?"), "prompts the user to describe the issue")
        XCTAssertTrue(report.body.contains("Job URL: https://acme.com/jobs/1"))
        XCTAssertTrue(report.body.contains("Company (parsed): Acme"))
        XCTAssertTrue(report.body.contains("Salary (parsed): USD200000–260000"))
        XCTAssertTrue(report.body.contains("Extraction: gemini-3.1-flash-lite (succeeded)"))
        XCTAssertTrue(report.body.contains("4200 chars · hash abc123def456ghi"))
        XCTAssertTrue(report.body.contains("macOS Version 15.0"))
        XCTAssertTrue(report.body.contains("job #42"))
    }

    func testReportOmitsSensitiveData() {
        // Report is built only from curated public fields, so private material can't leak in.
        let report = JobIssueReportBuilder.build(input())
        for secret in ["résumé", "resume", "personal", "fit score", "fitScore", "note"] {
            XCTAssertFalse(report.body.lowercased().contains(secret.lowercased()), "must not include \(secret)")
        }
    }

    func testUnknownFieldsRenderPlaceholderNotBlank() {
        let report = JobIssueReportBuilder.build(input(company: nil, title: "  "))
        XCTAssertEqual(report.title, "Job issue: (unknown) — (unknown)")
        XCTAssertTrue(report.body.contains("Company (parsed): (unknown)"))
    }

    func testNewIssueURLIsPrefilledWithLabelTitleBody() throws {
        let report = JobIssueReportBuilder.build(input())
        let url = try XCTUnwrap(GitHubIssueReporter.newIssueURL(report: report))
        XCTAssertTrue(url.absoluteString.hasPrefix("https://github.com/brooksc/jobhunt/issues/new"))
        let items = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
        XCTAssertEqual(items.first { $0.name == "labels" }?.value, "job-report")
        XCTAssertEqual(items.first { $0.name == "title" }?.value, "Job issue: Acme — Staff Engineer")
        XCTAssertTrue((items.first { $0.name == "body" }?.value ?? "").contains("Job URL:"))
    }

    func testOversizedReportDeclinesPrefillSoCallerFallsBackToBlank() {
        // A pathologically long parsed title blows the URL budget → prefill declined; caller opens the
        // blank issue and relies on the clipboard copy (never truncates the report).
        let huge = String(repeating: "A", count: 9000)
        let report = JobIssueReportBuilder.build(input(title: huge))
        XCTAssertNil(GitHubIssueReporter.newIssueURL(report: report), "oversized prefill is declined")
        XCTAssertTrue(GitHubIssueReporter.blankIssueURL.absoluteString.contains("labels=job-report"))
    }
}
