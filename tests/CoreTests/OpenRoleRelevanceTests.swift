import Foundation
import XCTest
@testable import JobhuntCore

/// Listing and ranking a company's other open roles (TASK-634).
final class OpenRoleListDecodeTests: XCTestCase {
    /// Shaped after the live payload (gitlab, checked 2026-08-09): `jobs` array, `location` nested,
    /// numeric `id`.
    private let payload = Data("""
    {
      "jobs": [
        {
          "id": 8503792002,
          "title": "Account Executive - Italy",
          "absolute_url": "https://job-boards.greenhouse.io/gitlab/jobs/8503792002",
          "updated_at": "2026-08-03T16:43:10-04:00",
          "first_published": "2026-05-02T09:00:00-04:00",
          "location": { "name": "Remote, Italy" }
        },
        { "id": 2, "title": "No URL", "location": { "name": "Nowhere" } },
        { "id": 3, "absolute_url": "https://example.com/x", "title": "   " }
      ],
      "meta": { "total": 3 }
    }
    """.utf8)

    func testDecodesRolesFromTheListPayload() throws {
        let roles = GreenhouseJobBoard.decodeRoles(payload)
        XCTAssertEqual(roles.count, 1)
        let role = try XCTUnwrap(roles.first)
        XCTAssertEqual(role.id, "8503792002")
        XCTAssertEqual(role.title, "Account Executive - Italy")
        XCTAssertEqual(role.locationName, "Remote, Italy")
        XCTAssertNotNil(role.updatedAt)
        XCTAssertNotNil(role.firstPublished)
    }

    /// A row with no URL can't be added and one with no title can't be judged — better skipped than
    /// rendered as a blank row the user can't act on.
    func testUnusableRowsAreSkipped() {
        XCTAssertEqual(GreenhouseJobBoard.decodeRoles(payload).count, 1)
    }

    func testGarbageDecodesToNothing() {
        XCTAssertTrue(GreenhouseJobBoard.decodeRoles(Data("nope".utf8)).isEmpty)
        XCTAssertTrue(GreenhouseJobBoard.decodeRoles(Data(#"{"jobs":"x"}"#.utf8)).isEmpty)
    }
}

final class OpenRoleRelevanceTests: XCTestCase {
    private func role(
        _ id: String,
        _ title: String,
        location: String? = nil,
        url: String? = nil
    ) -> GreenhouseJobBoard.OpenRole {
        GreenhouseJobBoard.OpenRole(
            id: id,
            title: title,
            locationName: location,
            absoluteURL: url ?? "https://boards.greenhouse.io/acme/jobs/\(id)",
            updatedAt: nil,
            firstPublished: nil
        )
    }

    /// The point of ranking: a board of 189 roles buries the two that matter.
    func testMostSimilarTitleRanksFirst() {
        let ranked = OpenRoleRelevance.rank(
            roles: [
                role("1", "Account Executive - Italy"),
                role("2", "Staff Platform Engineer"),
                role("3", "Recruiting Coordinator")
            ],
            title: "Senior Platform Engineer",
            location: nil
        )
        XCTAssertEqual(ranked.first?.role.id, "2")
        XCTAssertGreaterThan(ranked[0].titleOverlap, ranked[1].titleOverlap)
    }

    /// The posting the user is already looking at must not appear in its own "other roles" list.
    func testCurrentPostingIsExcluded() {
        let here = "https://boards.greenhouse.io/acme/jobs/1"
        let ranked = OpenRoleRelevance.rank(
            roles: [role("1", "Staff Engineer", url: here), role("2", "Staff Engineer")],
            title: "Staff Engineer",
            location: nil,
            excludingURLs: [here]
        )
        XCTAssertEqual(ranked.map(\.role.id), ["2"])
    }

    /// "Remote, Italy" and "Italy" are the same place for this purpose; exact equality would call
    /// them different and lose the signal on every remote posting.
    func testLocationMatchIgnoresTheRemotePrefix() {
        let ranked = OpenRoleRelevance.rank(
            roles: [role("1", "Account Executive", location: "Remote, Italy")],
            title: "Account Executive",
            location: "Italy"
        )
        XCTAssertTrue(ranked[0].sameLocation)
    }

    /// One shared word is usually "Engineer", which matches half the board — so "similar" needs two,
    /// or one plus a location match.
    func testSimilarityNeedsMoreThanOneCommonWord() {
        let weak = OpenRoleRelevance.rank(
            roles: [role("1", "Sales Engineer")], title: "Platform Engineer", location: nil
        )[0]
        XCTAssertEqual(weak.titleOverlap, 1)
        XCTAssertFalse(OpenRoleRelevance.isSimilar(weak))

        let strong = OpenRoleRelevance.rank(
            roles: [role("1", "Staff Platform Engineer")], title: "Platform Engineer", location: nil
        )[0]
        XCTAssertTrue(OpenRoleRelevance.isSimilar(strong))
    }

    /// One shared word plus the same location is enough — that combination is rarely a coincidence.
    func testOneWordPlusSameLocationCounts() {
        let scored = OpenRoleRelevance.rank(
            roles: [role("1", "Sales Engineer", location: "Berlin")],
            title: "Platform Engineer",
            location: "Berlin"
        )[0]
        XCTAssertTrue(OpenRoleRelevance.isSimilar(scored))
    }

    /// Stopwords must not create similarity: two roles sharing only "for" and "the" aren't alike.
    func testStopwordsDontCreateSimilarity() {
        let scored = OpenRoleRelevance.rank(
            roles: [role("1", "Manager for the Warehouse")],
            title: "Engineer for the Platform",
            location: nil
        )[0]
        XCTAssertEqual(scored.titleOverlap, 0)
    }

    /// Ties break on title so the list doesn't reshuffle between openings — a list that reorders on
    /// every open looks broken even when the ranking is right.
    func testOrderingIsStableAcrossCalls() {
        let roles = [role("1", "Zebra Engineer"), role("2", "Alpha Engineer")]
        let first = OpenRoleRelevance.rank(roles: roles, title: "Engineer", location: nil)
        let second = OpenRoleRelevance.rank(roles: roles.reversed(), title: "Engineer", location: nil)
        XCTAssertEqual(first.map(\.role.id), second.map(\.role.id))
        XCTAssertEqual(first.map(\.role.title), ["Alpha Engineer", "Zebra Engineer"])
    }

    func testNoTitleStillReturnsEverythingRatherThanNothing() {
        let ranked = OpenRoleRelevance.rank(
            roles: [role("1", "A"), role("2", "B")], title: nil, location: nil
        )
        XCTAssertEqual(ranked.count, 2)
        XCTAssertTrue(ranked.allSatisfy { $0.titleOverlap == 0 })
    }
}
