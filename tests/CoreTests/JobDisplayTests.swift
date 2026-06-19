import XCTest
@testable import JobhuntCore

/// Display-fallback helpers (TASK-525): a job stays legible before/without extraction.
final class JobDisplayTests: XCTestCase {
    private func makeJob(title: String? = nil, company: String? = nil, capture: Capture? = nil) -> Job {
        let job = Job(company: company, title: title)
        job.capture = capture
        return job
    }

    private func makeCapture(url: String, canonicalURL: String? = nil, pageTitle: String) -> Capture {
        Capture(url: url, canonicalURL: canonicalURL, pageTitle: pageTitle, rawHash: "h")
    }

    func testDisplayTitle_prefersExtractedTitle() {
        let job = makeJob(title: "Staff Engineer", capture: makeCapture(url: "https://x.com", pageTitle: "x — careers"))
        XCTAssertEqual(job.displayTitle, "Staff Engineer")
    }

    func testDisplayTitle_fallsBackToPageTitle_whenNoExtractedTitle() {
        let job = makeJob(capture: makeCapture(url: "https://acme.com/jobs/1", pageTitle: "Backend Engineer — Acme"))
        XCTAssertEqual(job.displayTitle, "Backend Engineer — Acme")
    }

    func testDisplayTitle_fallsBackToHost_whenPageTitleBlank() {
        let job = makeJob(capture: makeCapture(url: "https://www.greenhouse.io/x", pageTitle: "   "))
        XCTAssertEqual(job.displayTitle, "greenhouse.io")
    }

    func testDisplayTitle_untitled_whenNoCapture() {
        XCTAssertEqual(makeJob().displayTitle, "Untitled")
    }

    func testDisplayTitle_whitespaceTitleIsIgnored() {
        let job = makeJob(title: "  ", capture: makeCapture(url: "https://x.com", pageTitle: "Page Title"))
        XCTAssertEqual(job.displayTitle, "Page Title")
    }

    func testCaptureHost_stripsWWW_andPrefersCanonical() {
        let job = makeJob(capture: makeCapture(
            url: "https://jobs.example.com/1",
            canonicalURL: "https://www.example.com/1",
            pageTitle: "t"
        ))
        XCTAssertEqual(job.captureHost, "example.com")
    }

    func testDisplayCompany_fallsBackToHost() {
        let job = makeJob(capture: makeCapture(url: "https://boards.greenhouse.io/acme/jobs/9", pageTitle: "t"))
        XCTAssertEqual(job.displayCompany, "boards.greenhouse.io")
    }

    func testDisplayCompany_prefersExtractedCompany() {
        let job = makeJob(company: "Acme", capture: makeCapture(url: "https://boards.greenhouse.io/x", pageTitle: "t"))
        XCTAssertEqual(job.displayCompany, "Acme")
    }

    func testDisplayCompany_nilWhenNoCompanyAndNoCapture() {
        XCTAssertNil(makeJob().displayCompany)
    }
}
