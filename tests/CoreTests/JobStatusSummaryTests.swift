import XCTest
@testable import JobhuntCore

final class JobStatusSummaryTests: XCTestCase {

    private func makeJob(status: JobStatus = .pursuing, fitScore: Int? = nil,
                         company: String? = "Acme", title: String? = "Engineer",
                         extractionStatus: ExtractionStatus = .pending) -> Job {
        let j = Job(jobNumber: Int.random(in: 1...10000), status: status)
        j.fitScore = fitScore
        if fitScore != nil { j.fitStatus = .succeeded }
        j.company = company
        j.title = title
        j.extractionStatus = extractionStatus
        return j
    }

    /// Returns a job with no QualityChecker issues.
    private func makeCleanJob() -> Job {
        let j = Job(jobNumber: Int.random(in: 1...10000), status: .pursuing)
        j.company = "Acme"
        j.title = "Engineer"
        j.location = "Remote"
        j.remoteType = .remote
        j.salaryMin = 100000
        j.extractionStatus = .succeeded
        j.rawTextBytes = 2000
        j.cleanedTextBytes = 1500
        return j
    }

    func testZeroJobsProducesEmptyStats() {
        let s = JobStatusSummary(jobs: [])
        XCTAssertEqual(s.total, 0)
        XCTAssertEqual(s.active, 0)
        XCTAssertEqual(s.interviews, 0)
        XCTAssertEqual(s.offers, 0)
        XCTAssertEqual(s.rejected, 0)
        XCTAssertEqual(s.passed, 0)
        XCTAssertEqual(s.issueCount, 0)
        XCTAssertEqual(s.avgFitDisplay, "—")
    }

    func testCountsByStatus_representativeDataset() {
        let jobs: [Job] = [
            makeJob(status: .pursuing),
            makeJob(status: .pursuing),
            makeJob(status: .applied),
            makeJob(status: .interview),
            makeJob(status: .offer),
            makeJob(status: .rejected),
            makeJob(status: .passed),
            makeJob(status: .archived),
        ]
        let s = JobStatusSummary(jobs: jobs)
        XCTAssertEqual(s.total, 8)
        XCTAssertEqual(s.active, 4, "pursuing(2) + applied(1) + interview(1) = 4")
        XCTAssertEqual(s.interviews, 1)
        XCTAssertEqual(s.offers, 1)
        XCTAssertEqual(s.rejected, 1)
        XCTAssertEqual(s.passed, 1)
    }

    func testFunnelCounts_correctHierarchy() {
        let jobs: [Job] = [
            makeJob(status: .pursuing),
            makeJob(status: .applied),
            makeJob(status: .interview),
            makeJob(status: .offer),
        ]
        let s = JobStatusSummary(jobs: jobs)
        XCTAssertEqual(s.funnelCounts[0].label, "Tracked")
        XCTAssertEqual(s.funnelCounts[0].count, 4, "pursuing+applied+interview+offer")
        XCTAssertEqual(s.funnelCounts[1].label, "Applied")
        XCTAssertEqual(s.funnelCounts[1].count, 3, "applied+interview+offer")
        XCTAssertEqual(s.funnelCounts[2].label, "Interview")
        XCTAssertEqual(s.funnelCounts[2].count, 2, "interview+offer")
        XCTAssertEqual(s.funnelCounts[3].label, "Offer")
        XCTAssertEqual(s.funnelCounts[3].count, 1, "offer only")
    }

    func testAvgFit_withScores() {
        let jobs = [makeJob(fitScore: 80), makeJob(fitScore: 60), makeJob(fitScore: 70)]
        let s = JobStatusSummary(jobs: jobs)
        XCTAssertEqual(s.avgFitDisplay, "70")
    }

    func testAvgFit_noScores() {
        let jobs = [makeJob(fitScore: nil), makeJob(fitScore: nil)]
        let s = JobStatusSummary(jobs: jobs)
        XCTAssertEqual(s.avgFitDisplay, "—")
    }

    func testIssueCount_countsJobsWithAnyIssue() {
        let jobs: [Job] = [
            makeJob(extractionStatus: .failed),  // has issues
            makeJob(company: nil),               // has issues
            makeJob(title: nil),                 // has issues
            makeCleanJob(),                      // no issues — not counted
        ]
        let s = JobStatusSummary(jobs: jobs)
        XCTAssertEqual(s.issueCount, 3)
    }

    func testSinglePassEquivalence_multipleJobTypes() {
        var jobs = [Job]()
        for _ in 0..<50 { jobs.append(makeJob(status: .pursuing, fitScore: 80)) }
        for _ in 0..<20 { jobs.append(makeJob(status: .applied)) }
        for _ in 0..<10 { jobs.append(makeJob(status: .rejected)) }
        for _ in 0..<5  { jobs.append(makeJob(status: .archived)) }

        let s = JobStatusSummary(jobs: jobs)
        XCTAssertEqual(s.total, 85)
        XCTAssertEqual(s.active, 70, "pursuing(50)+applied(20)")
        XCTAssertEqual(s.rejected, 10)
        XCTAssertEqual(s.avgFitDisplay, "80", "All pursuing have score 80")
        XCTAssertEqual(s.countsByStatus[.pursuing], 50)
        XCTAssertEqual(s.countsByStatus[.applied], 20)
        XCTAssertEqual(s.countsByStatus[.archived], 5)
    }
}
