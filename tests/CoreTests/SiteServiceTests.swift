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

    // MARK: - createSite respects custom intervalDays

    func testCreateSite_customInterval_setsNextReviewAt() async throws {
        let container = try ModelContainerFactory.inMemory()
        let svc = SiteService(store: makeStore(container))

        _ = try await svc.createSite(url: "https://jobs.example.com", name: nil, intervalDays: 21)

        let ctx = ModelContext(container)
        let site = try XCTUnwrap(ctx.fetch(FetchDescriptor<Site>()).first)
        XCTAssertEqual(site.intervalDays, 21)
        let expected = Calendar.current.date(byAdding: .day, value: 21, to: Date())!
        let diff = site.nextReviewAt.map { abs($0.timeIntervalSince(expected)) } ?? 9999
        XCTAssertLessThan(diff, 5, "nextReviewAt should be approx now + intervalDays")
    }

    // MARK: - LocalizedError descriptions

    func testSiteServiceError_localizedDescription() {
        XCTAssertEqual(SiteServiceError.siteNotFound("x").localizedDescription, "Site not found")
    }
}
