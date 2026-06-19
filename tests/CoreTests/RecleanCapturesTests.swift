import SwiftData
import XCTest
@testable import JobhuntCore

/// Tests for BackgroundStore.recleanAllCaptures — the one-time re-clean migration that recomputes
/// cleanedDescription/cleanedHash for existing captures with the improved cleaner.
final class RecleanCapturesTests: XCTestCase {
    func testRecleanUpdatesDescriptionHashAndBytes() async throws {
        let store = try BackgroundStore(modelContainer: ModelContainerFactory.inMemory())
        let capture = Capture(
            url: "https://example.com/job",
            pageTitle: "Engineer",
            selectedText: "We are hiring a Senior Engineer to lead the platform.",
            visibleText: "Apply now\nWe are hiring a Senior Engineer to lead the platform.\nGreat benefits package.",
            cleanedDescription: "STALE",
            rawHash: "rh-reclean-1",
            cleanedHash: "stale-hash"
        )
        let job = Job(jobNumber: 1, title: "Engineer")
        job.capture = capture
        try await store.insert(capture)
        try await store.insert(job)

        let changed = try await store.recleanAllCaptures()
        XCTAssertEqual(changed, 1)

        let fetched = try await store.fetch(
            FetchDescriptor<Capture>(predicate: #Predicate { $0.rawHash == "rh-reclean-1" })
        ).first
        let cleaned = try XCTUnwrap(fetched?.cleanedDescription)

        XCTAssertNotEqual(cleaned, "STALE", "description recomputed")
        XCTAssertTrue(cleaned.contains("Great benefits package."), "real content kept")
        XCTAssertFalse(cleaned.contains("Apply now"), "boilerplate stripped")
        XCTAssertEqual(
            cleaned.components(separatedBy: "Senior Engineer to lead the platform").count - 1, 1,
            "selection not duplicated"
        )
        XCTAssertEqual(fetched?.cleanedHash, DuplicateDetector.cleanedHash(from: cleaned), "hash refreshed")
    }

    func testRecleanIsIdempotent() async throws {
        let store = try BackgroundStore(modelContainer: ModelContainerFactory.inMemory())
        let capture = Capture(
            url: "https://example.com/job2",
            pageTitle: "PM",
            visibleText: "The Role\nDrive product strategy across teams.",
            rawHash: "rh-reclean-2"
        )
        try await store.insert(capture)

        let first = try await store.recleanAllCaptures()
        XCTAssertEqual(first, 1, "first pass cleans the never-cleaned capture")
        let second = try await store.recleanAllCaptures()
        XCTAssertEqual(second, 0, "second pass is a no-op")
    }
}
