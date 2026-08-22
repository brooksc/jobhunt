import SwiftData
import XCTest
@testable import JobhuntCore

// MARK: - DataQualityScope (TASK-580)

/// The inclusion policy shared by the Data Quality view and the dashboard quality count.
final class DataQualityScopeTests: XCTestCase {
    func testEligibleStatusesExcludeTerminalAndDuplicate() {
        XCTAssertTrue(DataQualityScope.isEligible(.new))
        XCTAssertTrue(DataQualityScope.isEligible(.pursuing))
        for terminal in [JobStatus.passed, .archived, .closed, .duplicate] {
            XCTAssertFalse(DataQualityScope.isEligible(terminal), "\(terminal) must be excluded")
        }
    }

    func testIncludedMatchesDefaultViewSemantics() {
        // Active, unreviewed job with issues → included in the default (showReviewed = false) view.
        XCTAssertTrue(DataQualityScope.isIncluded(status: .new, hasReview: false, showReviewed: false))
        // Terminal status → never included.
        XCTAssertFalse(DataQualityScope.isIncluded(status: .archived, hasReview: false, showReviewed: false))
        XCTAssertFalse(DataQualityScope.isIncluded(status: .duplicate, hasReview: false, showReviewed: false))
        // Reviewed job → hidden by default, shown when showReviewed is on.
        XCTAssertFalse(DataQualityScope.isIncluded(status: .new, hasReview: true, showReviewed: false))
        XCTAssertTrue(DataQualityScope.isIncluded(status: .new, hasReview: true, showReviewed: true))
    }
}

final class QualityCheckerTests: XCTestCase {
    // MARK: - testMissingCompany

    func testMissingCompany() {
        let job = Job(company: nil, title: "Engineer", location: "Remote")
        job.remoteType = .remote
        job.salaryMin = 100_000
        job.extractionStatus = .succeeded

        let kinds = QualityChecker.issues(for: job)
        XCTAssertTrue(kinds.contains(.missingCompany), "Should flag missing company")
        XCTAssertFalse(kinds.contains(.missingTitle), "Should not flag title when present")
    }

    func testMissingCompanyEmptyString() {
        let job = Job(company: "", title: "Engineer", location: "SF")
        job.remoteType = .onsite
        job.salaryMin = 80000
        job.extractionStatus = .succeeded

        let kinds = QualityChecker.issues(for: job)
        XCTAssertTrue(kinds.contains(.missingCompany))
    }

    func testMissingCompanyUnknownValue() {
        // "unknown" should count as missing
        let job = Job(company: "unknown", title: "Engineer", location: "SF")
        job.remoteType = .onsite
        job.salaryMin = 80000
        job.extractionStatus = .succeeded

        let kinds = QualityChecker.issues(for: job)
        XCTAssertTrue(kinds.contains(.missingCompany))
    }

    func testNoIssuesWhenDataComplete() {
        let job = Job(
            company: "Acme Corp",
            title: "Staff Engineer",
            location: "San Francisco, CA"
        )
        job.remoteType = .hybrid
        job.salaryMin = 150_000
        job.extractionStatus = .succeeded

        let kinds = QualityChecker.issues(for: job)
        XCTAssertFalse(kinds.contains(.missingCompany))
        XCTAssertFalse(kinds.contains(.missingTitle))
        XCTAssertFalse(kinds.contains(.missingLocation))
        XCTAssertFalse(kinds.contains(.missingWorkMode))
        XCTAssertFalse(kinds.contains(.missingSalary))
    }

    // MARK: - testShortText

    func testShortRawText() {
        // No capture → raw size = 0 < 1000
        let job = Job(company: "Acme", title: "Engineer", location: "Remote")
        job.remoteType = .remote
        job.salaryMin = 100_000
        job.extractionStatus = .succeeded

        let kinds = QualityChecker.issues(for: job)
        XCTAssertTrue(kinds.contains(.shortRawText), "Should flag short raw text when no capture")
        XCTAssertTrue(kinds.contains(.shortCleanedText), "Should flag short cleaned text when no capture")
    }

    func testShortTextWithSmallCapture() throws {
        let container = try ModelContainerFactory.inMemory()
        let context = ModelContext(container)

        let job = Job(company: "Acme", title: "Engineer", location: "Remote")
        job.remoteType = .remote
        job.salaryMin = 100_000
        job.extractionStatus = .succeeded

        // Capture with short text (under 1000 bytes raw, under 700 cleaned)
        let shortText = String(repeating: "a", count: 500)
        let shortCleaned = String(repeating: "b", count: 300)
        let capture = Capture(
            url: "https://example.com/job/1",
            pageTitle: "Engineer at Acme",
            visibleText: shortText,
            cleanedDescription: shortCleaned,
            rawHash: "testhash123"
        )
        capture.job = job
        job.capture = capture

        context.insert(job)
        context.insert(capture)
        try context.save()

        let kinds = QualityChecker.issues(for: job)
        XCTAssertTrue(kinds.contains(.shortRawText), "500 bytes raw should flag shortRawText")
        XCTAssertTrue(kinds.contains(.shortCleanedText), "300 bytes cleaned should flag shortCleanedText")
    }

    func testNoShortTextWithLargeCapture() throws {
        let container = try ModelContainerFactory.inMemory()
        let context = ModelContext(container)

        let job = Job(company: "Acme", title: "Engineer", location: "Remote")
        job.remoteType = .remote
        job.salaryMin = 100_000
        job.extractionStatus = .succeeded

        let longText = String(repeating: "x", count: 2000)
        let longCleaned = String(repeating: "y", count: 1000)
        let capture = Capture(
            url: "https://example.com/job/2",
            pageTitle: "Engineer at Acme",
            visibleText: longText,
            cleanedDescription: longCleaned,
            rawHash: "testhash456"
        )
        capture.job = job
        job.capture = capture

        context.insert(job)
        context.insert(capture)
        try context.save()

        let kinds = QualityChecker.issues(for: job)
        XCTAssertFalse(kinds.contains(.shortRawText))
        XCTAssertFalse(kinds.contains(.shortCleanedText))
    }

    // MARK: - testExtractionFailed

    func testExtractionFailed() {
        let job = Job(
            company: "Acme",
            title: "Engineer",
            location: "Remote",
            extractionStatus: .failed
        )
        job.remoteType = .remote
        job.salaryMin = 100_000

        let kinds = QualityChecker.issues(for: job)
        XCTAssertTrue(kinds.contains(.extractionFailed), "Should flag failed extraction")
        XCTAssertFalse(kinds.contains(.extractionPending))
    }

    func testExtractionPending() {
        let job = Job(
            company: "Acme",
            title: "Engineer",
            location: "Remote",
            extractionStatus: .pending
        )
        job.remoteType = .remote
        job.salaryMin = 100_000

        let kinds = QualityChecker.issues(for: job)
        XCTAssertTrue(kinds.contains(.extractionPending))
        XCTAssertFalse(kinds.contains(.extractionFailed))
    }

    func testExtractionSucceededNotFlagged() {
        let job = Job(
            company: "Acme",
            title: "Engineer",
            location: "Remote",
            extractionStatus: .succeeded
        )
        job.remoteType = .remote
        job.salaryMin = 100_000

        let kinds = QualityChecker.issues(for: job)
        XCTAssertFalse(kinds.contains(.extractionFailed))
        XCTAssertFalse(kinds.contains(.extractionPending))
    }

    // MARK: - TASK-459: pending extraction suppresses missing-extracted-field issues

    func testPendingJobWithMissingFieldsSuppressesFieldIssues() {
        let job = Job(extractionStatus: .pending) // no company/title/location/work mode/salary
        let kinds = QualityChecker.issues(for: job)
        XCTAssertTrue(kinds.contains(.extractionPending))
        for missing in [
            QualityIssueKind.missingCompany,
            .missingTitle,
            .missingLocation,
            .missingWorkMode,
            .missingSalary
        ] {
            XCTAssertFalse(kinds.contains(missing), "\(missing) must be suppressed while extraction is pending")
        }
    }

    func testSucceededJobWithMissingFieldsStillReportsThem() {
        let job = Job(extractionStatus: .succeeded)
        let kinds = QualityChecker.issues(for: job)
        XCTAssertTrue(kinds.contains(.missingCompany))
        XCTAssertTrue(kinds.contains(.missingTitle))
        XCTAssertTrue(kinds.contains(.missingLocation))
    }

    func testFailedJobWithMissingFieldsReportsFailureAndFields() {
        let job = Job(extractionStatus: .failed)
        let kinds = QualityChecker.issues(for: job)
        XCTAssertTrue(kinds.contains(.extractionFailed))
        XCTAssertTrue(kinds.contains(.missingCompany), "failed extraction stays actionable with field gaps")
    }

    // MARK: - TASK-458: isHighSeverity reflects the issue KIND, not the count

    func testIsHighSeverity_singleHighKindIsHigh() {
        XCTAssertTrue(QualityIssue(jobID: "j1", kinds: [.extractionFailed]).isHighSeverity)
    }

    func testIsHighSeverity_multipleLowKindsIsNotHigh() {
        let issue = QualityIssue(jobID: "j2", kinds: [.missingSalary, .missingWorkMode, .shortRawText])
        XCTAssertFalse(issue.isHighSeverity, "three low-severity kinds is not high severity")
    }

    func testIsHighSeverity_mixedIsHigh() {
        // missingTitle is high-severity.
        XCTAssertTrue(QualityIssue(jobID: "j3", kinds: [.missingSalary, .missingTitle]).isHighSeverity)
    }

    // MARK: - testIssuesForAllJobs

    func testIssuesForAllJobs() throws {
        let cleanJob = Job(
            company: "Acme",
            title: "Engineer",
            location: "Remote",
            extractionStatus: .succeeded
        )
        cleanJob.remoteType = .remote
        cleanJob.salaryMin = 100_000

        // Job with issues (no company, no title)
        let badJob = Job(extractionStatus: .failed)

        let issues = QualityChecker.issuesForAllJobs([cleanJob, badJob])
        // cleanJob may have shortRawText/shortCleanedText (no capture), so could appear too
        XCTAssertTrue(issues.contains(where: { $0.jobID == badJob.id }))

        let badIssue = try XCTUnwrap(issues.first(where: { $0.jobID == badJob.id }))
        XCTAssertTrue(badIssue.kinds.contains(.missingCompany))
        XCTAssertTrue(badIssue.kinds.contains(.extractionFailed))
    }

    // MARK: - testMissingWorkMode

    func testMissingWorkModeWhenNil() {
        let job = Job(company: "Acme", title: "Engineer", location: "Remote")
        job.remoteType = nil
        job.salaryMin = 100_000
        job.extractionStatus = .succeeded

        let kinds = QualityChecker.issues(for: job)
        XCTAssertTrue(kinds.contains(.missingWorkMode))
    }

    func testMissingWorkModeWhenUnknown() {
        let job = Job(company: "Acme", title: "Engineer", location: "Remote")
        job.remoteType = .unknown
        job.salaryMin = 100_000
        job.extractionStatus = .succeeded

        let kinds = QualityChecker.issues(for: job)
        XCTAssertTrue(kinds.contains(.missingWorkMode))
    }

    func testWorkModeNotFlaggedWhenSet() {
        let job = Job(company: "Acme", title: "Engineer", location: "Remote")
        job.remoteType = .remote
        job.salaryMin = 100_000
        job.extractionStatus = .succeeded

        let kinds = QualityChecker.issues(for: job)
        XCTAssertFalse(kinds.contains(.missingWorkMode))
    }

    // MARK: - testMissingSalary

    func testMissingSalaryWhenAllNil() {
        let job = Job(company: "Acme", title: "Engineer", location: "Remote")
        job.remoteType = .remote
        job.extractionStatus = .succeeded
        // salaryMin, salaryMax, salaryNote all nil

        let kinds = QualityChecker.issues(for: job)
        XCTAssertTrue(kinds.contains(.missingSalary))
    }

    func testSalaryNotFlaggedWhenMinSet() {
        let job = Job(company: "Acme", title: "Engineer", location: "Remote", salaryMin: 120_000)
        job.remoteType = .remote
        job.extractionStatus = .succeeded

        let kinds = QualityChecker.issues(for: job)
        XCTAssertFalse(kinds.contains(.missingSalary))
    }

    func testSalaryNotFlaggedWhenNoteSet() {
        let job = Job(company: "Acme", title: "Engineer", location: "Remote", salaryNote: "Competitive")
        job.remoteType = .remote
        job.extractionStatus = .succeeded

        let kinds = QualityChecker.issues(for: job)
        XCTAssertFalse(kinds.contains(.missingSalary))
    }

    // MARK: - testStaleExtraction

    func testStaleExtraction() {
        let job = Job(company: "Acme", title: "Engineer", location: "Remote", extractionStatus: .succeeded)
        job.remoteType = .remote
        job.salaryMin = 100_000
        // Set extractedAt to 30 days ago
        job.extractedAt = Calendar.current.date(byAdding: .day, value: -30, to: Date())

        let kinds = QualityChecker.issues(for: job)
        XCTAssertTrue(kinds.contains(.staleExtraction), "30 days old should flag staleExtraction")
    }

    func testNotStaleWhenRecent() {
        let job = Job(company: "Acme", title: "Engineer", location: "Remote", extractionStatus: .succeeded)
        job.remoteType = .remote
        job.salaryMin = 100_000
        job.extractedAt = Calendar.current.date(byAdding: .day, value: -5, to: Date())

        let kinds = QualityChecker.issues(for: job)
        XCTAssertFalse(kinds.contains(.staleExtraction))
    }

    // MARK: - Permanently failed extractions (TASK-676 #3)

    /// A job whose extraction failed has no company, title, location or salary, so in the Jobs list it
    /// is a near-blank row with no indication that anything went wrong. It must be findable somewhere,
    /// and Data Quality is that somewhere: a high-severity issue with its own filter chip.
    func testAFailedExtractionIsFlaggedRatherThanLeftBlank() {
        let job = Job(company: "", title: "", location: "", extractionStatus: .failed)

        let kinds = QualityChecker.issues(for: job)
        XCTAssertTrue(kinds.contains(.extractionFailed), "\(kinds)")
        XCTAssertTrue(QualityIssueKind.extractionFailed.isHighSeverity, "a blank row is not a minor gap")
        XCTAssertTrue(DataQualityScope.isIncluded(status: .new, hasReview: false, showReviewed: false))
    }

    /// Pending is not failed. While extraction is still queued the missing fields are expected, and
    /// calling that a failure would flag every fresh capture (TASK-459).
    func testAPendingExtractionIsNotReportedAsFailed() {
        let job = Job(company: "", title: "", location: "", extractionStatus: .pending)

        let kinds = QualityChecker.issues(for: job)
        XCTAssertFalse(kinds.contains(.extractionFailed))
        XCTAssertTrue(kinds.contains(.extractionPending))
    }
}
