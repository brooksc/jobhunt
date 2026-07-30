import XCTest
@testable import JobhuntCore

/// Microsoft's board renders the posting in a detail pane with `?pid=<id>` in the address bar, but
/// emits ONE `<link rel="canonical">` for the whole search page — identical for every job. Ingestion
/// treats a canonical match as proof two captures are the same posting and rewrites the existing
/// capture in place, so capturing a second Microsoft job overwrote the first: the new job never
/// appeared and the old one's content was destroyed (job #2, four times in one session).
final class CanonicalURLPolicyTests: XCTestCase {
    private let searchPageCanonical =
        "http://apply.careers.microsoft.com/careers?query=Technical%20Program%20Manager&location=&start=0"

    private func captureURL(pid: String) -> String {
        "https://apply.careers.microsoft.com/careers?query=Technical+Program+Manager&start=0&pid=\(pid)"
    }

    // MARK: - The reported failure

    func testSearchPageCanonicalIsRejected() {
        XCTAssertFalse(CanonicalURLPolicy.identifiesSamePosting(
            canonical: searchPageCanonical, captureURL: captureURL(pid: "1970393556855691")
        ))
    }

    /// The property that actually matters: two different postings must not end up sharing an identity.
    func testTwoPostingsDoNotCollapseToOneCanonical() {
        let first = CanonicalURLPolicy.trustworthyCanonical(
            searchPageCanonical, captureURL: captureURL(pid: "1970393556631918")
        )
        let second = CanonicalURLPolicy.trustworthyCanonical(
            searchPageCanonical, captureURL: captureURL(pid: "1970393556855691")
        )
        XCTAssertNil(first)
        XCTAssertNil(second)
    }

    /// The case that worked: a real job URL whose canonical names the same posting.
    func testMatchingJobCanonicalIsKept() {
        XCTAssertTrue(CanonicalURLPolicy.identifiesSamePosting(
            canonical: "http://apply.careers.microsoft.com/careers/job/1970393556855691",
            captureURL: captureURL(pid: "1970393556855691")
        ))
    }

    // MARK: - Legitimate canonicals must survive

    /// An embedded board canonicalizing to its ATS is the main reason canonical support exists — the
    /// id appears in the canonical's PATH rather than its query, and must still count.
    func testEmbeddedBoardCanonicalToATSIsKept() {
        XCTAssertTrue(CanonicalURLPolicy.identifiesSamePosting(
            canonical: "https://boards.greenhouse.io/acme/jobs/4844291101",
            captureURL: "https://careers.acme.com/?gh_jid=4844291101"
        ))
    }

    func testCrossHostCanonicalIsAllowedWhenTheIDMatches() {
        XCTAssertTrue(CanonicalURLPolicy.identifiesSamePosting(
            canonical: "https://jobs.ashbyhq.com/livekit/876e0840",
            captureURL: "https://livekit.io/careers?ashby_jid=876e0840"
        ))
    }

    /// No identifier in the query means nothing suggests the canonical is broader — unchanged
    /// behaviour for the path-based URLs that make up most captures.
    func testPathBasedURLsKeepTheirCanonical() {
        XCTAssertTrue(CanonicalURLPolicy.identifiesSamePosting(
            canonical: "https://example.com/jobs/123?utm_source=x",
            captureURL: "https://example.com/jobs/123"
        ))
    }

    func testIDMatchIsCaseInsensitive() {
        XCTAssertTrue(CanonicalURLPolicy.identifiesSamePosting(
            canonical: "https://example.com/jobs/AbC123",
            captureURL: "https://example.com/careers?jobId=abc123"
        ))
    }

    // MARK: - trustworthyCanonical wrapper

    func testEmptyAndMissingCanonicalsBecomeNil() {
        XCTAssertNil(CanonicalURLPolicy.trustworthyCanonical(nil, captureURL: "https://example.com/j/1"))
        XCTAssertNil(CanonicalURLPolicy.trustworthyCanonical("   ", captureURL: "https://example.com/j/1"))
    }

    func testTrustworthyCanonicalPassesThroughAGoodValue() {
        let canonical = "https://boards.greenhouse.io/acme/jobs/999"
        XCTAssertEqual(
            CanonicalURLPolicy.trustworthyCanonical(canonical, captureURL: "https://acme.com/c?gh_jid=999"),
            canonical
        )
    }

    // MARK: - Posting-id extraction

    func testRecognisesTheCommonPostingIDParams() {
        for param in ["pid", "gh_jid", "ashby_jid", "jobId", "currentJobId", "requisitionId"] {
            XCTAssertEqual(
                CanonicalURLPolicy.postingID(inQueryOf: "https://x.com/c?\(param)=42&other=1"),
                "42", param
            )
        }
    }

    func testIgnoresNonIdentifyingParams() {
        XCTAssertNil(CanonicalURLPolicy.postingID(inQueryOf: "https://x.com/c?query=TPM&start=0&sort_by=relevance"))
    }

    func testEmptyIDValueIsIgnored() {
        XCTAssertNil(CanonicalURLPolicy.postingID(inQueryOf: "https://x.com/c?pid=&start=0"))
    }
}
