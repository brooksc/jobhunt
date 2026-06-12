import SwiftData
import XCTest
@testable import JobhuntCore

// MARK: - SavedSearchMatchesTests

final class SavedSearchMatchesTests: XCTestCase {
    // MARK: - Helpers

    private func makeJob(
        id: String = UUID().uuidString,
        jobNumber: Int? = nil,
        company: String? = nil,
        title: String? = nil,
        location: String? = nil,
        status: JobStatus = .new,
        remoteType: RemoteType? = nil,
        fitScore: Int? = nil,
        rating: Int? = nil,
        salaryMin: Int? = nil,
        capturedAt: Date? = nil
    ) -> Job {
        let job = Job(
            id: id,
            jobNumber: jobNumber,
            company: company,
            title: title,
            location: location,
            remoteType: remoteType,
            salaryMin: salaryMin,
            status: status,
            fitScore: fitScore,
            rating: rating
        )
        job.capturedAtDenormalized = capturedAt
        return job
    }

    private func makeSearch(
        statusFilterRaw: [String] = [],
        remoteFilterRaw: [String] = [],
        searchText: String = "",
        minFitScore: Int? = nil,
        minRating: Int? = nil,
        minSalary: Int? = nil,
        recentDays: Int? = nil
    ) -> SavedSearch {
        SavedSearch(
            name: "test",
            statusFilterRaw: statusFilterRaw,
            remoteFilterRaw: remoteFilterRaw,
            searchText: searchText,
            minFitScore: minFitScore,
            minRating: minRating,
            minSalary: minSalary,
            recentDays: recentDays
        )
    }

    // MARK: - Empty filters

    func testEmptyFiltersMatchAnyJob() {
        let search = makeSearch()
        let job = makeJob(company: "Acme", status: .pursuing)
        XCTAssertTrue(search.matches(job))
    }

    // MARK: - Status filter

    func testStatusFilter_matchingStatus() {
        let search = makeSearch(statusFilterRaw: [JobStatus.pursuing.rawValue])
        let job = makeJob(status: .pursuing)
        XCTAssertTrue(search.matches(job))
    }

    func testStatusFilter_nonMatchingStatus() {
        let search = makeSearch(statusFilterRaw: [JobStatus.pursuing.rawValue])
        let job = makeJob(status: .new)
        XCTAssertFalse(search.matches(job))
    }

    func testStatusFilter_emptyAllowsAll() {
        let search = makeSearch(statusFilterRaw: [])
        let job = makeJob(status: .rejected)
        XCTAssertTrue(search.matches(job))
    }

    // MARK: - Remote type filter

    func testRemoteFilter_matchingRemoteType() {
        let search = makeSearch(remoteFilterRaw: [RemoteType.remote.rawValue])
        let job = makeJob(remoteType: .remote)
        XCTAssertTrue(search.matches(job))
    }

    func testRemoteFilter_nonMatchingRemoteType() {
        let search = makeSearch(remoteFilterRaw: [RemoteType.remote.rawValue])
        let job = makeJob(remoteType: .onsite)
        XCTAssertFalse(search.matches(job))
    }

    func testRemoteFilter_nilRemoteTypeExcluded() {
        let search = makeSearch(remoteFilterRaw: [RemoteType.remote.rawValue])
        let job = makeJob(remoteType: nil)
        XCTAssertFalse(search.matches(job))
    }

    // MARK: - minFitScore filter

    func testMinFitScore_aboveThreshold() {
        let search = makeSearch(minFitScore: 70)
        let job = makeJob(fitScore: 80)
        XCTAssertTrue(search.matches(job))
    }

    func testMinFitScore_equalThreshold() {
        let search = makeSearch(minFitScore: 70)
        let job = makeJob(fitScore: 70)
        XCTAssertTrue(search.matches(job))
    }

    func testMinFitScore_belowThreshold() {
        let search = makeSearch(minFitScore: 70)
        let job = makeJob(fitScore: 50)
        XCTAssertFalse(search.matches(job))
    }

    func testMinFitScore_nilScoreTreatedAsZero() {
        let search = makeSearch(minFitScore: 50)
        let job = makeJob(fitScore: nil)
        XCTAssertFalse(search.matches(job))
    }

    // MARK: - minRating filter

    func testMinRating_aboveThreshold() {
        let search = makeSearch(minRating: 3)
        let job = makeJob(rating: 4)
        XCTAssertTrue(search.matches(job))
    }

    func testMinRating_belowThreshold() {
        let search = makeSearch(minRating: 3)
        let job = makeJob(rating: 2)
        XCTAssertFalse(search.matches(job))
    }

    // MARK: - minSalary filter

    func testMinSalary_salaryMinAboveThreshold() {
        let search = makeSearch(minSalary: 100_000)
        let job = makeJob(salaryMin: 120_000)
        XCTAssertTrue(search.matches(job))
    }

    func testMinSalary_salaryMinBelowThreshold() {
        let search = makeSearch(minSalary: 100_000)
        let job = makeJob(salaryMin: 80_000)
        XCTAssertFalse(search.matches(job))
    }

    func testMinSalary_nilSalaryTreatedAsZero() {
        let search = makeSearch(minSalary: 50_000)
        let job = makeJob(salaryMin: nil)
        XCTAssertFalse(search.matches(job))
    }

    // MARK: - recentDays filter

    func testRecentDays_jobWithinWindow() {
        let search = makeSearch(recentDays: 7)
        let recentDate = Calendar.current.date(byAdding: .day, value: -3, to: Date())!
        let job = makeJob(capturedAt: recentDate)
        XCTAssertTrue(search.matches(job))
    }

    func testRecentDays_jobOutsideWindow() {
        let search = makeSearch(recentDays: 7)
        let oldDate = Calendar.current.date(byAdding: .day, value: -30, to: Date())!
        let job = makeJob(capturedAt: oldDate)
        XCTAssertFalse(search.matches(job))
    }

    func testRecentDays_usesCapturedAtDenormalized() {
        let search = makeSearch(recentDays: 7)
        // capturedAt is recent, createdAt will default to Date() in Job init
        let recentDate = Calendar.current.date(byAdding: .day, value: -2, to: Date())!
        let job = makeJob(capturedAt: recentDate)
        XCTAssertTrue(search.matches(job))
    }

    func testRecentDays_fallsBackToCreatedAtWhenCapturedAtNil() {
        let search = makeSearch(recentDays: 7)
        // No capturedAt set — matches() should use createdAt (which defaults to Date())
        let job = makeJob(capturedAt: nil)
        XCTAssertTrue(search.matches(job))
    }

    // MARK: - searchText filter

    func testSearchText_matchesCompany() {
        let search = makeSearch(searchText: "acme")
        let job = makeJob(company: "Acme Corp")
        XCTAssertTrue(search.matches(job))
    }

    func testSearchText_matchesTitle() {
        let search = makeSearch(searchText: "engineer")
        let job = makeJob(title: "Senior Engineer")
        XCTAssertTrue(search.matches(job))
    }

    func testSearchText_matchesLocation() {
        let search = makeSearch(searchText: "new york")
        let job = makeJob(location: "New York, NY")
        XCTAssertTrue(search.matches(job))
    }

    func testSearchText_noMatch() {
        let search = makeSearch(searchText: "google")
        let job = makeJob(company: "Acme", title: "Engineer")
        XCTAssertFalse(search.matches(job))
    }

    func testSearchText_jobNumberMatchWithHash() {
        let search = makeSearch(searchText: "#42")
        let job = makeJob(jobNumber: 42, company: "Acme")
        XCTAssertTrue(search.matches(job))
    }

    func testSearchText_jobNumberMatchPlain() {
        let search = makeSearch(searchText: "42")
        let job = makeJob(jobNumber: 42)
        XCTAssertTrue(search.matches(job))
    }

    func testSearchText_jobNumberNoMatch() {
        let search = makeSearch(searchText: "#99")
        let job = makeJob(jobNumber: 42)
        XCTAssertFalse(search.matches(job))
    }

    func testSearchText_caseInsensitive() {
        let search = makeSearch(searchText: "ACME")
        let job = makeJob(company: "acme corp")
        XCTAssertTrue(search.matches(job))
    }

    // MARK: - Combined filters

    func testCombinedFilters_allMatch() {
        let search = makeSearch(
            statusFilterRaw: [JobStatus.pursuing.rawValue],
            searchText: "engineer",
            minFitScore: 60
        )
        let job = makeJob(title: "Engineer", status: .pursuing, fitScore: 75)
        XCTAssertTrue(search.matches(job))
    }

    func testCombinedFilters_oneFailsExcludesJob() {
        let search = makeSearch(
            statusFilterRaw: [JobStatus.pursuing.rawValue],
            searchText: "engineer",
            minFitScore: 60
        )
        // fitScore too low
        let job = makeJob(title: "Engineer", status: .pursuing, fitScore: 30)
        XCTAssertFalse(search.matches(job))
    }
}
