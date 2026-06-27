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
        let job = makeJob(salaryMin: 80000)
        XCTAssertFalse(search.matches(job))
    }

    func testMinSalary_nilSalaryTreatedAsZero() {
        let search = makeSearch(minSalary: 50000)
        let job = makeJob(salaryMin: nil)
        XCTAssertFalse(search.matches(job))
    }

    // MARK: - recentDays filter

    func testRecentDays_jobWithinWindow() throws {
        let search = makeSearch(recentDays: 7)
        let recentDate = try XCTUnwrap(Calendar.current.date(byAdding: .day, value: -3, to: Date()))
        let job = makeJob(capturedAt: recentDate)
        XCTAssertTrue(search.matches(job))
    }

    func testRecentDays_jobOutsideWindow() throws {
        let search = makeSearch(recentDays: 7)
        let oldDate = try XCTUnwrap(Calendar.current.date(byAdding: .day, value: -30, to: Date()))
        let job = makeJob(capturedAt: oldDate)
        XCTAssertFalse(search.matches(job))
    }

    func testRecentDays_usesCapturedAtDenormalized() throws {
        let search = makeSearch(recentDays: 7)
        // capturedAt is recent, createdAt will default to Date() in Job init
        let recentDate = try XCTUnwrap(Calendar.current.date(byAdding: .day, value: -2, to: Date()))
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

// MARK: - SavedSearchCriteriaTests (TASK-364)

/// Covers the Sendable projection the Sidebar uses to compute badge counts off-main, including
/// count correctness after status/field/search changes.
final class SavedSearchCriteriaTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    private func fields(
        status: JobStatus = .new,
        remoteType: RemoteType? = nil,
        fitScore: Int? = nil,
        rating: Int? = nil,
        salaryMin: Int? = nil,
        capturedAt: Date? = nil,
        company: String? = nil,
        title: String? = nil,
        jobNumber: Int? = nil
    ) -> JobMatchFields {
        let job = Job(
            jobNumber: jobNumber, company: company, title: title,
            remoteType: remoteType, salaryMin: salaryMin,
            status: status, fitScore: fitScore, rating: rating
        )
        job.capturedAtDenormalized = capturedAt
        return JobMatchFields(job: job)
    }

    private func count(_ search: SavedSearch, _ items: [JobMatchFields]) -> Int {
        let criteria = SavedSearchCriteria(search)
        return items.count(where: { criteria.matches($0, now: now) })
    }

    func testStatusFilterCount() {
        let search = SavedSearch(name: "pursuing", statusFilterRaw: [JobStatus.pursuing.rawValue])
        let items = [fields(status: .pursuing), fields(status: .new), fields(status: .pursuing)]
        XCTAssertEqual(count(search, items), 2)
    }

    func testCountUpdatesWhenAStatusChanges() {
        let search = SavedSearch(name: "pursuing", statusFilterRaw: [JobStatus.pursuing.rawValue])
        let before = [fields(status: .new), fields(status: .new)]
        XCTAssertEqual(count(search, before), 0)
        // Flip one job to pursuing → count reflects it.
        let after = [fields(status: .pursuing), fields(status: .new)]
        XCTAssertEqual(count(search, after), 1)
    }

    func testCountUpdatesWhenAFilteredFieldChanges() {
        let search = SavedSearch(name: "fit60", minFitScore: 60)
        XCTAssertEqual(count(search, [fields(fitScore: 30)]), 0)
        XCTAssertEqual(count(search, [fields(fitScore: 80)]), 1)
    }

    func testCountUpdatesWhenSearchCriteriaChange() {
        let items = [fields(fitScore: 50), fields(fitScore: 90)]
        XCTAssertEqual(count(SavedSearch(name: "a", minFitScore: 40), items), 2)
        XCTAssertEqual(count(SavedSearch(name: "b", minFitScore: 80), items), 1)
    }

    func testRecentDaysUsesInjectedNowDeterministically() {
        let search = SavedSearch(name: "recent", recentDays: 7)
        let within = fields(capturedAt: now.addingTimeInterval(-3 * 86400))
        let outside = fields(capturedAt: now.addingTimeInterval(-30 * 86400))
        XCTAssertEqual(count(search, [within, outside]), 1)
    }

    func testTextAndJobNumberMatch() {
        let textSearch = SavedSearch(name: "t", searchText: "acme")
        XCTAssertEqual(count(textSearch, [fields(company: "Acme Corp"), fields(company: "Other")]), 1)
        let numSearch = SavedSearch(name: "n", searchText: "#42")
        XCTAssertEqual(count(numSearch, [fields(jobNumber: 42), fields(jobNumber: 7)]), 1)
    }

    // TASK-573: the shared matcher used by both saved-search counts and the live Jobs list consults
    // display title/company, location, cleaned description, and job number.
    func testSharedTextNumberMatcher() {
        func m(
            _ q: String,
            company: String? = nil,
            title: String = "Untitled",
            location: String? = nil,
            desc: String? = nil,
            number: Int? = nil
        ) -> Bool {
            SavedSearchCriteria.textNumberMatch(
                query: q, displayCompany: company, displayTitle: title,
                location: location, cleanedDescription: desc, jobNumber: number
            )
        }
        XCTAssertTrue(m("swiftui", desc: "We use SwiftUI daily"))
        XCTAssertTrue(m("acme.example.com", company: "acme.example.com"))
        XCTAssertTrue(m("staff ios", title: "Staff iOS Engineer"))
        XCTAssertTrue(m("remote", location: "Remote, US"))
        XCTAssertTrue(m("#42", number: 42))
        XCTAssertTrue(m("4", number: 42)) // substring
        XCTAssertTrue(m("   "), "empty query matches everything")
        XCTAssertFalse(m("python", company: "Acme", title: "Engineer", location: "NYC", desc: "Swift", number: 7))
    }

    /// TASK-573 AC#4: the count path finds an un-extracted job by its capture's page title, host, and
    /// cleaned description — the same fields the live Jobs list searches.
    func testSavedSearchCountUsesCaptureFallbacksAndCleanedDescription() {
        let capture = Capture(
            url: "https://acme.example.com/jobs/1",
            pageTitle: "Staff iOS Engineer",
            cleanedDescription: "We build with SwiftUI and Combine.",
            rawHash: "h"
        )
        let job = Job(jobNumber: 42, status: .new) // no extracted title/company
        job.capture = capture
        let f = JobMatchFields(job: job)

        XCTAssertEqual(count(SavedSearch(name: "title", searchText: "staff ios"), [f]), 1)
        XCTAssertEqual(count(SavedSearch(name: "host", searchText: "acme.example.com"), [f]), 1)
        XCTAssertEqual(count(SavedSearch(name: "desc", searchText: "swiftui"), [f]), 1)
        XCTAssertEqual(count(SavedSearch(name: "none", searchText: "python"), [f]), 0)
    }

    func testEqualFieldsHashAndCompareEqual() {
        // Stability of the change signal: identical inputs produce equal, equally-hashing snapshots.
        // capturedAt is pinned because a real Job's createdAt is stable across re-snapshots.
        let cap = now
        let a = fields(status: .new, fitScore: 80, capturedAt: cap, company: "Acme")
        let b = fields(status: .new, fitScore: 80, capturedAt: cap, company: "Acme")
        XCTAssertEqual(a, b)
        XCTAssertEqual(a.hashValue, b.hashValue)
        let c = fields(status: .pursuing, fitScore: 80, capturedAt: cap, company: "Acme")
        XCTAssertNotEqual(a, c)
    }
}

// MARK: - SavedSearchTokenIDTests (TASK-572)

/// The token-identity mapping the Jobs view uses to tell a programmatic saved-search apply (keep the
/// search active) from a user token edit (clear it). Shared with `JobSearchToken.id` via `SearchTokenID`
/// so the apply path and the retain decision can't drift.
final class SavedSearchTokenIDTests: XCTestCase {
    func testExpectedTokenIDsCoverEveryFilterField() {
        let search = SavedSearch(
            name: "all",
            statusFilterRaw: [JobStatus.pursuing.rawValue, JobStatus.applied.rawValue],
            remoteFilterRaw: [RemoteType.remote.rawValue],
            minFitScore: 70,
            minRating: 4,
            minSalary: 150_000,
            recentDays: 30
        )
        XCTAssertEqual(search.expectedTokenIDs, [
            SearchTokenID.status("pursuing"),
            SearchTokenID.status("applied"),
            SearchTokenID.remote("remote"),
            SearchTokenID.fitScore(70),
            SearchTokenID.rating(4),
            SearchTokenID.salary(150_000),
            SearchTokenID.recentDays(30)
        ])
    }

    func testEmptySearchHasNoTokenIDs() {
        XCTAssertTrue(SavedSearch(name: "empty").expectedTokenIDs.isEmpty)
    }

    /// The identity strings are stable — the Jobs view compares persisted tokens against these, so a
    /// silent format change would break saved-search retention (the bug this guards).
    func testTokenIDFormatIsStable() {
        XCTAssertEqual(SearchTokenID.status("pursuing"), "status:pursuing")
        XCTAssertEqual(SearchTokenID.remote("remote"), "remote:remote")
        XCTAssertEqual(SearchTokenID.fitScore(70), "fitScore:70")
        XCTAssertEqual(SearchTokenID.salary(150_000), "salary:150000")
        XCTAssertEqual(SearchTokenID.rating(4), "rating:4")
        XCTAssertEqual(SearchTokenID.recentDays(30), "recent:30")
    }
}
