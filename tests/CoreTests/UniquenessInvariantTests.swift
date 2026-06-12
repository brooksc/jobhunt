import SwiftData
import XCTest
@testable import JobhuntCore

/// Tests that @Attribute(.unique) constraints are enforced at the SQLite level.
///
/// These tests use file-backed stores because SwiftData in-memory stores do not
/// always surface SQLite uniqueness violations the same way as on-disk stores.
/// Each test creates an isolated temp file and removes it on teardown.
///
/// Note on behavior: When SwiftData encounters a uniqueness conflict it may silently
/// merge/upsert rows rather than throwing during ctx.save(). The observable result
/// is that only ONE row survives with the duplicate key — not two distinct rows.
final class UniquenessInvariantTests: XCTestCase {

    // MARK: - Helpers

    private func makeFileContainer() throws -> (ModelContainer, URL) {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("uniqueness_\(UUID().uuidString).store")
        let schema = Schema(SchemaV1.models)
        let config = ModelConfiguration(url: url)
        let container = try ModelContainer(
            for: schema,
            migrationPlan: JobhuntMigrationPlan.self,
            configurations: config
        )
        return (container, url)
    }

    // MARK: - Job.jobNumber

    func testJobNumberUniqueConstraintDeduplicates() throws {
        let (container, url) = try makeFileContainer()
        defer { try? FileManager.default.removeItem(at: url) }
        let ctx = ModelContext(container)

        let job1 = Job(jobNumber: 42, title: "First")
        let job2 = Job(jobNumber: 42, title: "Second")
        ctx.insert(job1)
        ctx.insert(job2)

        // Save may throw or silently merge — either is acceptable enforcement.
        // We only assert the post-save invariant: at most one row with jobNumber == 42.
        _ = try? ctx.save()

        let fetched = try ctx.fetch(FetchDescriptor<Job>())
        let matching = fetched.filter { $0.jobNumber == 42 }
        XCTAssertLessThanOrEqual(matching.count, 1,
            "At most one Job row may have jobNumber == 42 after save")
    }

    func testJobNumberDistinctValuesAreKept() throws {
        let (container, url) = try makeFileContainer()
        defer { try? FileManager.default.removeItem(at: url) }
        let ctx = ModelContext(container)

        ctx.insert(Job(jobNumber: 100, title: "Alpha"))
        ctx.insert(Job(jobNumber: 101, title: "Beta"))
        try ctx.save()

        let fetched = try ctx.fetch(FetchDescriptor<Job>())
        XCTAssertEqual(fetched.count, 2, "Two Jobs with distinct jobNumbers must both persist")
    }

    func testJobNumberNilIsNotUnique() throws {
        // nil jobNumber should not trigger the uniqueness constraint — multiple nil rows allowed.
        let (container, url) = try makeFileContainer()
        defer { try? FileManager.default.removeItem(at: url) }
        let ctx = ModelContext(container)

        ctx.insert(Job(title: "No Number A"))
        ctx.insert(Job(title: "No Number B"))
        try ctx.save()

        let fetched = try ctx.fetch(FetchDescriptor<Job>())
        XCTAssertEqual(fetched.count, 2, "Multiple Jobs with nil jobNumber must all persist")
    }

    // MARK: - Capture.rawHash

    func testCaptureRawHashUniqueConstraintDeduplicates() throws {
        let (container, url) = try makeFileContainer()
        defer { try? FileManager.default.removeItem(at: url) }
        let ctx = ModelContext(container)

        let c1 = Capture(url: "https://a.com", pageTitle: "A", rawHash: "dup_hash")
        let c2 = Capture(url: "https://b.com", pageTitle: "B", rawHash: "dup_hash")
        ctx.insert(c1)
        ctx.insert(c2)
        _ = try? ctx.save()

        let fetched = try ctx.fetch(FetchDescriptor<Capture>())
        let matching = fetched.filter { $0.rawHash == "dup_hash" }
        XCTAssertLessThanOrEqual(matching.count, 1,
            "At most one Capture row may have rawHash == 'dup_hash' after save")
    }

    func testCaptureRawHashDistinctValuesAreKept() throws {
        let (container, url) = try makeFileContainer()
        defer { try? FileManager.default.removeItem(at: url) }
        let ctx = ModelContext(container)

        ctx.insert(Capture(url: "https://a.com", pageTitle: "A", rawHash: "hash_a"))
        ctx.insert(Capture(url: "https://b.com", pageTitle: "B", rawHash: "hash_b"))
        try ctx.save()

        let fetched = try ctx.fetch(FetchDescriptor<Capture>())
        XCTAssertEqual(fetched.count, 2, "Two Captures with distinct rawHashes must both persist")
    }

    // MARK: - Site.origin

    func testSiteOriginUniqueConstraintDeduplicates() throws {
        let (container, url) = try makeFileContainer()
        defer { try? FileManager.default.removeItem(at: url) }
        let ctx = ModelContext(container)

        let s1 = Site(origin: "example.com", url: "https://example.com/jobs1")
        let s2 = Site(origin: "example.com", url: "https://example.com/jobs2")
        ctx.insert(s1)
        ctx.insert(s2)
        _ = try? ctx.save()

        let fetched = try ctx.fetch(FetchDescriptor<Site>())
        let matching = fetched.filter { $0.origin == "example.com" }
        XCTAssertLessThanOrEqual(matching.count, 1,
            "At most one Site row may have origin == 'example.com' after save")
    }

    func testSiteOriginDistinctValuesAreKept() throws {
        let (container, url) = try makeFileContainer()
        defer { try? FileManager.default.removeItem(at: url) }
        let ctx = ModelContext(container)

        ctx.insert(Site(origin: "alpha.com", url: "https://alpha.com"))
        ctx.insert(Site(origin: "beta.com", url: "https://beta.com"))
        try ctx.save()

        let fetched = try ctx.fetch(FetchDescriptor<Site>())
        XCTAssertEqual(fetched.count, 2, "Two Sites with distinct origins must both persist")
    }

    // MARK: - DuplicateDecision.cleanedHash

    func testDuplicateDecisionCleanedHashUniqueConstraintDeduplicates() throws {
        let (container, url) = try makeFileContainer()
        defer { try? FileManager.default.removeItem(at: url) }
        let ctx = ModelContext(container)

        let d1 = DuplicateDecision(cleanedHash: "dup_cleaned", decision: "keep")
        let d2 = DuplicateDecision(cleanedHash: "dup_cleaned", decision: "discard")
        ctx.insert(d1)
        ctx.insert(d2)
        _ = try? ctx.save()

        let fetched = try ctx.fetch(FetchDescriptor<DuplicateDecision>())
        let matching = fetched.filter { $0.cleanedHash == "dup_cleaned" }
        XCTAssertLessThanOrEqual(matching.count, 1,
            "At most one DuplicateDecision row may have cleanedHash == 'dup_cleaned' after save")
    }

    func testDuplicateDecisionCleanedHashDistinctValuesAreKept() throws {
        let (container, url) = try makeFileContainer()
        defer { try? FileManager.default.removeItem(at: url) }
        let ctx = ModelContext(container)

        ctx.insert(DuplicateDecision(cleanedHash: "hash_x", decision: "keep"))
        ctx.insert(DuplicateDecision(cleanedHash: "hash_y", decision: "discard"))
        try ctx.save()

        let fetched = try ctx.fetch(FetchDescriptor<DuplicateDecision>())
        XCTAssertEqual(fetched.count, 2,
            "Two DuplicateDecisions with distinct cleanedHashes must both persist")
    }
}
