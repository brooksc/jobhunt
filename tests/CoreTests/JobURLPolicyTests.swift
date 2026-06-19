import SwiftData
import XCTest
@testable import JobhuntCore

/// TASK-460: centralized job-URL precedence across export / MCP / availability / detail.
final class JobURLPolicyTests: XCTestCase {
    // MARK: - sourceURL = canonical ?? captureURL

    func testSourceURL_prefersCanonical() {
        XCTAssertEqual(
            JobURLPolicy.sourceURL(canonicalURL: "https://canon.example/x", captureURL: "https://raw.example/y"),
            "https://canon.example/x"
        )
    }

    func testSourceURL_fallsBackToCaptureURL() {
        XCTAssertEqual(
            JobURLPolicy.sourceURL(canonicalURL: nil, captureURL: "https://raw.example/y"),
            "https://raw.example/y"
        )
    }

    func testSourceURL_blankCanonicalSkipped() {
        XCTAssertEqual(
            JobURLPolicy.sourceURL(canonicalURL: "   ", captureURL: "https://raw.example/y"),
            "https://raw.example/y"
        )
    }

    func testSourceURL_allMissingIsNil() {
        XCTAssertNil(JobURLPolicy.sourceURL(canonicalURL: nil, captureURL: nil))
        XCTAssertNil(JobURLPolicy.sourceURL(canonicalURL: "", captureURL: "  "))
    }

    // MARK: - applicationURL = applicationURL ?? canonical ?? captureURL

    func testApplicationURL_prefersExplicitApplicationURL() {
        XCTAssertEqual(
            JobURLPolicy.applicationURL(
                applicationURL: "https://apply.example/a",
                canonicalURL: "https://canon.example/x",
                captureURL: "https://raw.example/y"
            ),
            "https://apply.example/a"
        )
    }

    func testApplicationURL_fallsBackThroughCanonicalThenCapture() {
        XCTAssertEqual(
            JobURLPolicy.applicationURL(
                applicationURL: nil,
                canonicalURL: "https://canon.example/x",
                captureURL: "https://raw.example/y"
            ),
            "https://canon.example/x"
        )
        XCTAssertEqual(
            JobURLPolicy.applicationURL(applicationURL: nil, canonicalURL: nil, captureURL: "https://raw.example/y"),
            "https://raw.example/y"
        )
    }

    func testApplicationURL_blankApplicationSkipped() {
        XCTAssertEqual(
            JobURLPolicy.applicationURL(applicationURL: "  ", canonicalURL: nil, captureURL: "https://raw.example/y"),
            "https://raw.example/y"
        )
    }

    func testApplicationURL_allMissingIsNil() {
        XCTAssertNil(JobURLPolicy.applicationURL(applicationURL: nil, canonicalURL: nil, captureURL: nil))
    }

    // MARK: - displayURL = canonical ?? captureURL ?? applicationURL

    func testDisplayURL_prefersSourceListingOverApplication() {
        // Even with an application URL present, "View Posting" opens the listing.
        XCTAssertEqual(
            JobURLPolicy.displayURL(
                applicationURL: "https://apply.example/a",
                canonicalURL: "https://canon.example/x",
                captureURL: "https://raw.example/y"
            ),
            "https://canon.example/x"
        )
    }

    func testDisplayURL_fallsBackToApplicationWhenNoCapture() {
        XCTAssertEqual(
            JobURLPolicy.displayURL(applicationURL: "https://apply.example/a", canonicalURL: nil, captureURL: nil),
            "https://apply.example/a"
        )
    }

    func testDisplayURL_allMissingIsNil() {
        XCTAssertNil(JobURLPolicy.displayURL(applicationURL: nil, canonicalURL: nil, captureURL: nil))
    }

    // MARK: - Job convenience wiring

    func testJobConveniences_useCaptureRelationship() throws {
        let container = try ModelContainerFactory.inMemory()
        let store = ModelContext(container)
        let capture = Capture(url: "https://raw.example/y", pageTitle: "t", rawHash: "h")
        capture.canonicalURL = "https://canon.example/x"
        let job = Job(jobNumber: 1, applicationURL: "https://apply.example/a")
        job.capture = capture
        store.insert(capture)
        store.insert(job)

        XCTAssertEqual(JobURLPolicy.sourceURL(job: job), "https://canon.example/x")
        XCTAssertEqual(JobURLPolicy.applicationURL(job: job), "https://apply.example/a")
        XCTAssertEqual(
            JobURLPolicy.availabilityCheckURL(job: job),
            "https://apply.example/a",
            "availability check uses application-URL precedence"
        )
        XCTAssertEqual(JobURLPolicy.displayURL(job: job), "https://canon.example/x")
    }
}
