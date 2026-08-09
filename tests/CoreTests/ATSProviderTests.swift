import Foundation
import XCTest
@testable import JobhuntCore

/// Routing a job's ATS id to the provider that can answer for it (TASK-636).
final class ATSRegistryTests: XCTestCase {
    func testEachVendorRoutesToItsProvider() {
        XCTAssertEqual(ATSRegistry.provider(forATSID: "gh:123")?.name, "Greenhouse")
        XCTAssertEqual(ATSRegistry.provider(forATSID: "lever:spotify:abc")?.name, "Lever")
        XCTAssertEqual(ATSRegistry.provider(forATSID: "ashby:ramp:abc")?.name, "Ashby")
        XCTAssertEqual(ATSRegistry.provider(forATSID: "wd:tenant:R-1")?.name, "Workday")
    }

    /// LinkedIn ids and bespoke career sites have no authoritative source, and must keep today's
    /// HTML behaviour rather than being handed to a provider that would guess.
    func testUnsupportedSourcesHaveNoProvider() {
        XCTAssertNil(ATSRegistry.provider(forATSID: "li:456"))
        XCTAssertNil(ATSRegistry.provider(forATSID: "unknown:1"))
    }

    /// The ATS id usually lives on the capture URL — a canonicalized application URL may have
    /// dropped the `?gh_jid=`. Resolution scans every URL rather than trusting one.
    func testResolveScansEveryURLAndSkipsUnusableOnes() throws {
        let resolved = try XCTUnwrap(ATSRegistry.resolve(urls: [
            nil,
            "https://example.com/careers/some-role",
            "https://careers.acme.com/?gh_jid=4567"
        ]))
        XCTAssertEqual(resolved.atsID, "gh:4567")
        XCTAssertEqual(resolved.provider.name, "Greenhouse")
    }

    func testResolveReturnsNilWhenNothingIsRecognised() {
        XCTAssertNil(ATSRegistry.resolve(urls: ["https://example.com/jobs/1", nil]))
    }
}

/// Lever's board payload (shape checked live against api.lever.co/v0/postings/spotify, 2026-08-09).
final class LeverProviderTests: XCTestCase {
    private let provider = LeverProvider()

    private var entries: [[String: Any]] {
        [[
            "id": "890b2c0f-f46f-4a4b-bb73-3a6af6e0edd5",
            "text": "Advertiser Solutions Vendor Lead",
            "hostedUrl": "https://jobs.lever.co/spotify/890b2c0f",
            "createdAt": 1_784_569_799_619,
            "descriptionPlain": "Sell what you love.",
            "additionalPlain": "You have 5 years of experience.",
            "categories": ["location": "London", "department": "Advertising"]
        ], [
            "id": "no-title",
            "hostedUrl": "https://jobs.lever.co/spotify/x",
            "descriptionPlain": "x"
        ]]
    }

    func testParsesOurATSIDForm() throws {
        let parsed = try XCTUnwrap(LeverProvider.parse("lever:spotify:abc-123"))
        XCTAssertEqual(parsed.company, "spotify")
        XCTAssertEqual(parsed.postingID, "abc-123")
        XCTAssertNil(LeverProvider.parse("lever:spotify"))
        XCTAssertNil(LeverProvider.parse("gh:1"))
    }

    /// The requirements live in `additionalPlain`, not `descriptionPlain` — using only the first
    /// would hand extraction a posting with no requirements in it.
    func testDescriptionJoinsTheIntroAndTheRequirements() throws {
        let posting = try XCTUnwrap(provider.posting(from: entries[0], company: "spotify"))
        XCTAssertTrue(posting.contentPlain.contains("Sell what you love"), posting.contentPlain)
        XCTAssertTrue(posting.contentPlain.contains("5 years"), posting.contentPlain)
        XCTAssertEqual(posting.title, "Advertiser Solutions Vendor Lead")
        XCTAssertEqual(posting.locationName, "London")
        XCTAssertEqual(posting.providerName, "Lever")
    }

    /// Lever stamps `createdAt` in **milliseconds**. Reading it as seconds would date every posting
    /// to 1970 and make the entire corpus look stale.
    func testCreatedAtIsMillisecondsNotSeconds() throws {
        let posting = try XCTUnwrap(provider.posting(from: entries[0], company: "spotify"))
        let published = try XCTUnwrap(posting.firstPublished)
        let year = Calendar(identifier: .gregorian).component(.year, from: published)
        XCTAssertGreaterThan(year, 2020, "epoch-milliseconds misread as seconds")
    }

    /// Lever publishes no update timestamp at all — inventing one would make freshness lie.
    func testNoUpdateTimestamp() throws {
        XCTAssertNil(try XCTUnwrap(provider.posting(from: entries[0], company: "spotify")).updatedAt)
    }

    func testRolesSkipRowsWithoutATitle() {
        let roles = LeverProvider.roles(from: entries)
        XCTAssertEqual(roles.count, 1)
        XCTAssertEqual(roles.first?.title, "Advertiser Solutions Vendor Lead")
    }

    func testEmptyDescriptionIsNotAPosting() {
        XCTAssertNil(provider.posting(from: ["id": "x", "text": "T"], company: "spotify"))
    }
}

/// Ashby's board payload (shape checked live against api.ashbyhq.com/posting-api/job-board/ramp,
/// 2026-08-09).
final class AshbyProviderTests: XCTestCase {
    private let provider = AshbyProvider()

    private var entries: [[String: Any]] {
        [[
            "id": "34413f8d-26bf-4bbc-8ade-eb309a0e2245",
            "title": " Security Engineer, Cloud",
            "location": "New York, NY (HQ)",
            "jobUrl": "https://jobs.ashbyhq.com/ramp/34413f8d",
            "publishedAt": "2026-04-07T17:12:35.753+00:00",
            "descriptionPlain": "Keep the cloud safe.",
            "isListed": true
        ], [
            "id": "hidden",
            "title": "Hidden Role",
            "jobUrl": "https://jobs.ashbyhq.com/ramp/hidden",
            "descriptionPlain": "x",
            "isListed": false
        ]]
    }

    func testParsesPostingWithFractionalSecondTimestamp() throws {
        let posting = try XCTUnwrap(provider.posting(from: entries[0], org: "ramp"))
        XCTAssertEqual(posting.title, "Security Engineer, Cloud", "title should be trimmed")
        XCTAssertEqual(posting.contentPlain, "Keep the cloud safe.")
        XCTAssertNotNil(posting.firstPublished)
        XCTAssertEqual(posting.providerName, "Ashby")
        // Ashby returns `updatedAt: null` on plenty of live rows.
        XCTAssertNil(posting.updatedAt)
    }

    /// `isListed == false` means the employer has hidden it from their own board — suggesting it as
    /// an open role would be worse than omitting it.
    func testUnlistedRolesAreOmitted() {
        let roles = AshbyProvider.roles(from: entries)
        XCTAssertEqual(roles.map(\.id), ["34413f8d-26bf-4bbc-8ade-eb309a0e2245"])
    }

    /// A row with no `isListed` key is treated as listed — absent isn't hidden.
    func testMissingIsListedDefaultsToVisible() {
        let roles = AshbyProvider.roles(from: [[
            "id": "x", "title": "Role", "jobUrl": "https://jobs.ashbyhq.com/ramp/x"
        ]])
        XCTAssertEqual(roles.count, 1)
    }
}

/// Workday answers liveness only, on purpose.
final class WorkdayProviderTests: XCTestCase {
    /// A `fetchPosting` returning a search-result summary would let the refresh overwrite a real
    /// capture with a stub, so this provider implements nothing but liveness.
    func testWorkdayOffersNoContentOrRoles() async {
        let provider = WorkdayProvider()
        let posting = await provider.fetchPosting(
            atsID: "wd:tenant:R-1", company: nil, urlString: "https://x.myworkdayjobs.com/",
            session: .shared
        )
        let roles = await provider.listOpenRoles(
            atsID: "wd:tenant:R-1", company: nil, urlString: "https://x.myworkdayjobs.com/",
            session: .shared
        )
        XCTAssertNil(posting)
        XCTAssertTrue(roles.isEmpty)
    }

    /// An unparseable Workday URL is indeterminate, not "removed" — the distinction that keeps a
    /// transient failure from mass-expiring live jobs.
    func testUnparseableURLIsIndeterminate() async {
        let alive = await WorkdayProvider().isAlive(
            atsID: "wd:tenant:R-1", company: nil, urlString: "not a url", session: .shared
        )
        XCTAssertNil(alive)
    }
}
