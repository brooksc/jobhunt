import SwiftData
import XCTest
@testable import JobhuntCore

final class SiteServiceTests: XCTestCase {

    private func makeStore(_ container: ModelContainer) -> BackgroundStore {
        BackgroundStore(modelContainer: container)
    }

    // MARK: - Not-found errors

    func testUpdateSite_missingID_throws() async throws {
        let container = try ModelContainerFactory.inMemory()
        let svc = SiteService(store: makeStore(container))

        do {
            try await svc.updateSite(id: "nonexistent-site", name: "New Name", excludeState: nil)
            XCTFail("Expected notFound error")
        } catch BackgroundStoreError.notFound {
            // expected
        }
    }

    func testDeleteSite_missingID_throws() async throws {
        let container = try ModelContainerFactory.inMemory()
        let svc = SiteService(store: makeStore(container))

        do {
            try await svc.deleteSite(id: "nonexistent-site")
            XCTFail("Expected notFound error")
        } catch BackgroundStoreError.notFound {
            // expected
        }
    }

    func testSetSiteState_missingID_throws() async throws {
        let container = try ModelContainerFactory.inMemory()
        let svc = SiteService(store: makeStore(container))

        do {
            try await svc.setSiteState(siteID: "nonexistent-site", state: .exclude)
            XCTFail("Expected notFound error")
        } catch BackgroundStoreError.notFound {
            // expected
        }
    }

    // MARK: - Upsert on duplicate origin

    func testCreateSite_duplicateOrigin_returnsExistingID() async throws {
        let container = try ModelContainerFactory.inMemory()
        let svc = SiteService(store: makeStore(container))

        let id1 = try await svc.createSite(url: "https://example.com/jobs", name: "Example")
        let id2 = try await svc.createSite(url: "https://example.com/careers", name: "ExampleUpdated")

        XCTAssertEqual(id1, id2, "Second createSite with same origin must return existing site ID")
        let ctx = ModelContext(container)
        let sites = try ctx.fetch(FetchDescriptor<Site>())
        XCTAssertEqual(sites.count, 1, "Duplicate origin must not create a second Site row")
        XCTAssertEqual(sites.first?.companyName, "ExampleUpdated", "Name should be updated on duplicate create")
    }

    // MARK: - Interval change recomputes nextReviewAt

    func testUpdateSite_intervalChange_recomputesNextReviewAt() async throws {
        let container = try ModelContainerFactory.inMemory()
        let store = makeStore(container)
        let svc = SiteService(store: store)

        let lastReviewed = Calendar.current.date(byAdding: .day, value: -5, to: Date())!
        let siteID = UUID().uuidString
        let site = Site(
            id: siteID,
            origin: "https://example.com",
            url: "https://example.com/jobs",
            intervalDays: 30,
            lastReviewedAt: lastReviewed
        )
        try await store.insert(site)

        try await svc.updateSite(id: siteID, name: nil, excludeState: nil, intervalDays: 7)

        let ctx = ModelContext(container)
        let updated = try ctx.fetch(FetchDescriptor<Site>()).first!
        XCTAssertEqual(updated.intervalDays, 7)
        let expected = Calendar.current.date(byAdding: .day, value: 7, to: lastReviewed)!
        let diff = updated.nextReviewAt.map { abs($0.timeIntervalSince(expected)) } ?? 9999
        XCTAssertLessThan(diff, 2, "nextReviewAt must be lastReviewedAt + newIntervalDays")
    }

    // MARK: - TASK-301: New sites have nil nextReviewAt

    func testCreateSite_hasNilNextReviewAt() async throws {
        let container = try ModelContainerFactory.inMemory()
        let svc = SiteService(store: makeStore(container))

        _ = try await svc.createSite(url: "https://example.com/jobs", name: "Example")

        let ctx = ModelContext(container)
        let site = try XCTUnwrap(ctx.fetch(FetchDescriptor<Site>()).first)
        XCTAssertNil(site.nextReviewAt, "New site must have nil nextReviewAt until first review")
        XCTAssertEqual(site.state, .notReviewed)
    }

    func testCreateSite_customInterval_hasNilNextReviewAt() async throws {
        let container = try ModelContainerFactory.inMemory()
        let svc = SiteService(store: makeStore(container))

        _ = try await svc.createSite(url: "https://jobs.example.com", name: nil, intervalDays: 21)

        let ctx = ModelContext(container)
        let site = try XCTUnwrap(ctx.fetch(FetchDescriptor<Site>()).first)
        XCTAssertEqual(site.intervalDays, 21)
        XCTAssertNil(site.nextReviewAt, "New site must have nil nextReviewAt until first review")
    }

    // MARK: - TASK-303: markReviewed creates a SiteReview record

    func testMarkReviewed_createsSiteReviewRecord() async throws {
        let container = try ModelContainerFactory.inMemory()
        let store = makeStore(container)
        let svc = SiteService(store: store)

        let siteID = try await svc.createSite(url: "https://example.com/jobs", name: "Example")
        try await svc.markReviewed(siteID: siteID)

        let ctx = ModelContext(container)
        let reviews = try ctx.fetch(FetchDescriptor<SiteReview>())
        XCTAssertEqual(reviews.count, 1, "markReviewed must create one SiteReview record")
        XCTAssertEqual(reviews.first?.siteOrigin, "https://example.com")
        XCTAssertNotNil(reviews.first?.reviewedAt)
        XCTAssertNotNil(reviews.first?.nextReviewAt)
    }

    // MARK: - TASK-304: upsertSiteReview persists note

    func testUpsertSiteReview_persistsNote() async throws {
        let container = try ModelContainerFactory.inMemory()
        let svc = SiteService(store: makeStore(container))

        _ = try await svc.upsertSiteReview(
            url: "https://example.com/jobs",
            title: "Jobs",
            intervalDays: 14,
            note: "Looks promising"
        )

        let ctx = ModelContext(container)
        let review = try XCTUnwrap(ctx.fetch(FetchDescriptor<SiteReview>()).first)
        XCTAssertEqual(review.note, "Looks promising")
    }

    // MARK: - LocalizedError descriptions

    func testSiteServiceError_localizedDescription() {
        XCTAssertEqual(SiteServiceError.siteNotFound("x").localizedDescription, "Site not found")
    }
}
