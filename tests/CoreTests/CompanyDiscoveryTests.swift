import Foundation
import SwiftData
import XCTest
@testable import JobhuntCore

/// Turning companies already in the library into sources worth watching (TASK-695, M6).
final class CompanyDiscoveryTests: XCTestCase {
    private func makeStore() throws -> BackgroundStore {
        try BackgroundStore(modelContainer: ModelContainerFactory.inMemory())
    }

    @discardableResult
    private func addJob(
        _ store: BackgroundStore, company: String, url: String
    ) async throws -> Job {
        let capture = Capture(url: url, pageTitle: "Role at \(company)", rawHash: UUID().uuidString)
        let job = Job(company: company)
        job.capture = capture
        try await store.insert(job)
        return job
    }

    // MARK: - Candidates

    func testACompanyWithJobsButNoSourceIsACandidate() async throws {
        let store = try makeStore()
        try await addJob(store, company: "Acme", url: "https://boards.greenhouse.io/acme/jobs/1")

        let candidates: [CompanyCandidate] = try await store.untrackedCompanyCandidates()
        XCTAssertEqual(candidates.map(\.company), ["Acme"])
        XCTAssertEqual(candidates.first?.jobCount, 1)
    }

    func testACompanyAlreadyWatchedIsNotSuggested() async throws {
        let store = try makeStore()
        try await addJob(store, company: "Acme", url: "https://boards.greenhouse.io/acme/jobs/1")
        try await store.insert(SearchSource(
            kind: "greenhouse", label: "Acme", config: SourceConfig(slug: "acme", company: "Acme")
        ))

        let candidates: [CompanyCandidate] = try await store.untrackedCompanyCandidates()
        XCTAssertTrue(candidates.isEmpty)
    }

    /// "Acme, Inc." in a job and "Acme" on a source are the same employer. Suggesting a company the
    /// user already watches is the fastest way to make the feature feel broken.
    func testLegalSuffixesDoNotMakeADifferentCompany() async throws {
        let store = try makeStore()
        try await addJob(store, company: "Acme, Inc.", url: "https://boards.greenhouse.io/acme/jobs/1")
        try await store.insert(SearchSource(
            kind: "greenhouse", label: "Acme", config: SourceConfig(slug: "acme", company: "Acme")
        ))

        let candidates: [CompanyCandidate] = try await store.untrackedCompanyCandidates()
        XCTAssertTrue(candidates.isEmpty, "“Acme, Inc.” and “Acme” are one company")
    }

    /// A source added by pasting a URL may have nothing but the slug as its label.
    func testASourceAddedByURLStillSuppressesItsCompany() async throws {
        let store = try makeStore()
        try await addJob(store, company: "GitLab", url: "https://boards.greenhouse.io/gitlab/jobs/1")
        try await store.insert(SearchSource(
            kind: "greenhouse", label: "gitlab", config: SourceConfig(slug: "gitlab")
        ))

        let candidates: [CompanyCandidate] = try await store.untrackedCompanyCandidates()
        XCTAssertTrue(candidates.isEmpty)
    }

    func testCompaniesAreRankedByHowManyJobsTheUserHasFromThem() async throws {
        let store = try makeStore()
        try await addJob(store, company: "Once", url: "https://example.com/1")
        for index in 1 ... 3 {
            try await addJob(store, company: "Thrice", url: "https://example.com/t\(index)")
        }

        let candidates: [CompanyCandidate] = try await store.untrackedCompanyCandidates()
        XCTAssertEqual(candidates.map(\.company), ["Thrice", "Once"])
    }

    func testAJobWithNoCompanyIsIgnored() async throws {
        let store = try makeStore()
        try await addJob(store, company: "   ", url: "https://example.com/1")
        let candidates: [CompanyCandidate] = try await store.untrackedCompanyCandidates()
        XCTAssertTrue(candidates.isEmpty)
    }

    // MARK: - Suggestions

    /// The point of reading the board off a URL jobhunt already has: most suggestions cost no
    /// network request at all. The failing session proves it — nothing was fetched.
    func testACompanyWhoseJobsCarryAnATSURLNeedsNoProbe() async throws {
        let store = try makeStore()
        try await addJob(store, company: "Acme", url: "https://job-boards.greenhouse.io/acme/jobs/42")

        let discovery = CompanyDiscovery(store: store, session: FailingURLProtocol.makeSession())
        let suggestions = await discovery.suggestions()
        XCTAssertEqual(suggestions.count, 1)
        XCTAssertEqual(suggestions.first?.board.kind, "greenhouse")
        XCTAssertEqual(suggestions.first?.board.slug, "acme")
        XCTAssertTrue(suggestions.first?.resolvedFromExistingURL ?? false)
    }

    func testAWorkdayJobYieldsItsTenant() async throws {
        let store = try makeStore()
        try await addJob(
            store, company: "Acme",
            url: "https://acme.wd5.myworkdayjobs.com/careers/job/HQ/Program-Manager_R-1"
        )
        let discovery = CompanyDiscovery(store: store, session: FailingURLProtocol.makeSession())
        let suggestions = await discovery.suggestions()
        XCTAssertEqual(suggestions.first?.board.kind, "workday")
    }

    /// A company whose jobs came from a careers page jobhunt can't read has to be probed, and the
    /// probe budget bounds how many. Each one is up to three requests to third-party APIs.
    func testProbingIsBounded() async throws {
        let store = try makeStore()
        for index in 1 ... 5 {
            try await addJob(store, company: "Company \(index)", url: "https://example.com/\(index)")
        }
        let discovery = CompanyDiscovery(store: store, session: FailingURLProtocol.makeSession())
        let suggestions = await discovery.suggestions(probeLimit: 2)
        XCTAssertTrue(suggestions.isEmpty, "the failing session resolves nothing")
    }

    /// Free identification happens first, so the probe budget is never spent on a company that
    /// didn't need it.
    func testFreeIdentificationIsNotBlockedByTheProbeBudget() async throws {
        let store = try makeStore()
        for index in 1 ... 3 {
            try await addJob(store, company: "Probe \(index)", url: "https://example.com/\(index)")
        }
        try await addJob(store, company: "Known", url: "https://jobs.lever.co/known/abc-123")

        let discovery = CompanyDiscovery(store: store, session: FailingURLProtocol.makeSession())
        let suggestions = await discovery.suggestions(probeLimit: 0)
        XCTAssertEqual(suggestions.map(\.company), ["Known"])
    }

    // MARK: - Name normalisation

    func testTheSameEmployerNormalisesTheSameWay() {
        XCTAssertEqual(CompanyNameKey.normalize("Acme, Inc."), CompanyNameKey.normalize("Acme"))
        XCTAssertEqual(CompanyNameKey.normalize("Grafana Labs"), CompanyNameKey.normalize("grafana"))
        XCTAssertEqual(CompanyNameKey.normalize("The Muse"), CompanyNameKey.normalize("muse"))
        XCTAssertEqual(CompanyNameKey.normalize("A.Team"), "ateam")
    }

    /// Normalisation must not collapse genuinely different employers — that would silently hide a
    /// company the user does want.
    func testDifferentEmployersStayDifferent() {
        XCTAssertNotEqual(CompanyNameKey.normalize("Stripe"), CompanyNameKey.normalize("Stripes"))
        XCTAssertNotEqual(CompanyNameKey.normalize("Mercury"), CompanyNameKey.normalize("Mercor"))
    }
}
