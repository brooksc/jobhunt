import XCTest
import SwiftData
@testable import JobhuntCore

final class QualityCheckerTests: XCTestCase {

    // MARK: - testMissingCompany

    func testMissingCompany() throws {
        let job = Job(company: nil, title: "Engineer", location: "Remote")
        job.remoteType = .remote
        job.salaryMin = 100_000
        job.extractionStatus = .succeeded

        let kinds = QualityChecker.issues(for: job)
        XCTAssertTrue(kinds.contains(.missingCompany), "Should flag missing company")
        XCTAssertFalse(kinds.contains(.missingTitle), "Should not flag title when present")
    }

    func testMissingCompanyEmptyString() throws {
        let job = Job(company: "", title: "Engineer", location: "SF")
        job.remoteType = .onsite
        job.salaryMin = 80_000
        job.extractionStatus = .succeeded

        let kinds = QualityChecker.issues(for: job)
        XCTAssertTrue(kinds.contains(.missingCompany))
    }

    func testMissingCompanyUnknownValue() throws {
        // "unknown" should count as missing
        let job = Job(company: "unknown", title: "Engineer", location: "SF")
        job.remoteType = .onsite
        job.salaryMin = 80_000
        job.extractionStatus = .succeeded

        let kinds = QualityChecker.issues(for: job)
        XCTAssertTrue(kinds.contains(.missingCompany))
    }

    func testNoIssuesWhenDataComplete() throws {
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

    func testShortRawText() throws {
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

    func testExtractionFailed() throws {
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

    func testExtractionPending() throws {
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

    func testExtractionSucceededNotFlagged() throws {
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

    func testMissingWorkModeWhenNil() throws {
        let job = Job(company: "Acme", title: "Engineer", location: "Remote")
        job.remoteType = nil
        job.salaryMin = 100_000
        job.extractionStatus = .succeeded

        let kinds = QualityChecker.issues(for: job)
        XCTAssertTrue(kinds.contains(.missingWorkMode))
    }

    func testMissingWorkModeWhenUnknown() throws {
        let job = Job(company: "Acme", title: "Engineer", location: "Remote")
        job.remoteType = .unknown
        job.salaryMin = 100_000
        job.extractionStatus = .succeeded

        let kinds = QualityChecker.issues(for: job)
        XCTAssertTrue(kinds.contains(.missingWorkMode))
    }

    func testWorkModeNotFlaggedWhenSet() throws {
        let job = Job(company: "Acme", title: "Engineer", location: "Remote")
        job.remoteType = .remote
        job.salaryMin = 100_000
        job.extractionStatus = .succeeded

        let kinds = QualityChecker.issues(for: job)
        XCTAssertFalse(kinds.contains(.missingWorkMode))
    }

    // MARK: - testMissingSalary

    func testMissingSalaryWhenAllNil() throws {
        let job = Job(company: "Acme", title: "Engineer", location: "Remote")
        job.remoteType = .remote
        job.extractionStatus = .succeeded
        // salaryMin, salaryMax, salaryNote all nil

        let kinds = QualityChecker.issues(for: job)
        XCTAssertTrue(kinds.contains(.missingSalary))
    }

    func testSalaryNotFlaggedWhenMinSet() throws {
        let job = Job(company: "Acme", title: "Engineer", location: "Remote", salaryMin: 120_000)
        job.remoteType = .remote
        job.extractionStatus = .succeeded

        let kinds = QualityChecker.issues(for: job)
        XCTAssertFalse(kinds.contains(.missingSalary))
    }

    func testSalaryNotFlaggedWhenNoteSet() throws {
        let job = Job(company: "Acme", title: "Engineer", location: "Remote", salaryNote: "Competitive")
        job.remoteType = .remote
        job.extractionStatus = .succeeded

        let kinds = QualityChecker.issues(for: job)
        XCTAssertFalse(kinds.contains(.missingSalary))
    }

    // MARK: - testStaleExtraction

    func testStaleExtraction() throws {
        let job = Job(company: "Acme", title: "Engineer", location: "Remote", extractionStatus: .succeeded)
        job.remoteType = .remote
        job.salaryMin = 100_000
        // Set extractedAt to 30 days ago
        job.extractedAt = Calendar.current.date(byAdding: .day, value: -30, to: Date())

        let kinds = QualityChecker.issues(for: job)
        XCTAssertTrue(kinds.contains(.staleExtraction), "30 days old should flag staleExtraction")
    }

    func testNotStaleWhenRecent() throws {
        let job = Job(company: "Acme", title: "Engineer", location: "Remote", extractionStatus: .succeeded)
        job.remoteType = .remote
        job.salaryMin = 100_000
        job.extractedAt = Calendar.current.date(byAdding: .day, value: -5, to: Date())

        let kinds = QualityChecker.issues(for: job)
        XCTAssertFalse(kinds.contains(.staleExtraction))
    }
}
