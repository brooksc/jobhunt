import XCTest
@testable import JobhuntCore

final class JobSearchLinksTests: XCTestCase {
    // MARK: - LinkedIn referral URL

    func testLinkedInConnectionsURL_encodesCompany() throws {
        let url = try XCTUnwrap(JobSearchLinks.linkedInConnectionsURL(company: "Akamai Technologies"))
        XCTAssertTrue(url.absoluteString.hasPrefix("https://www.linkedin.com/search/results/companies/"))
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems
        XCTAssertEqual(items?.first { $0.name == "keywords" }?.value, "Akamai Technologies")
    }

    func testLinkedInConnectionsURL_nilWhenNoCompany() {
        XCTAssertNil(JobSearchLinks.linkedInConnectionsURL(company: nil))
        XCTAssertNil(JobSearchLinks.linkedInConnectionsURL(company: "   "))
    }

    // MARK: - Google company-site search URL

    func testCompanySiteSearchURL_buildsQueryWithExclusions() throws {
        let url = try XCTUnwrap(JobSearchLinks.companySiteSearchURL(
            company: "Akamai",
            title: "Technical Program Manager"
        ))
        XCTAssertTrue(url.absoluteString.hasPrefix("https://www.google.com/search"))
        let q = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?.first { $0.name == "q" }?.value)
        XCTAssertTrue(q.contains("Akamai"))
        XCTAssertTrue(q.contains("Technical Program Manager"))
        XCTAssertTrue(q.contains("(careers OR jobs)"))
        XCTAssertTrue(q.contains("-site:linkedin.com"))
        XCTAssertTrue(q.contains("-site:indeed.com"))
    }

    func testCompanySiteSearchURL_nilWhenCompanyOrTitleMissing() {
        XCTAssertNil(JobSearchLinks.companySiteSearchURL(company: "Akamai", title: nil))
        XCTAssertNil(JobSearchLinks.companySiteSearchURL(company: nil, title: "Engineer"))
        XCTAssertNil(JobSearchLinks.companySiteSearchURL(company: " ", title: " "))
    }

    // MARK: - postingIsOnCompanySite

    func testPostingIsOnCompanySite_apexDomainMatches() {
        // The Google jobs case the user called out: company IS the domain.
        XCTAssertTrue(JobSearchLinks.postingIsOnCompanySite(
            company: "Google", postingURL: "https://www.google.com/careers/jobs/123"
        ))
    }

    func testPostingIsOnCompanySite_atsPathMatches() {
        // Company slug in an ATS path counts as "direct" too.
        XCTAssertTrue(JobSearchLinks.postingIsOnCompanySite(
            company: "GitLab", postingURL: "https://boards.greenhouse.io/gitlab/jobs/8509676002"
        ))
    }

    func testPostingIsOnCompanySite_aggregatorDoesNotMatch() {
        XCTAssertFalse(JobSearchLinks.postingIsOnCompanySite(
            company: "Google", postingURL: "https://www.linkedin.com/jobs/view/4424422798/"
        ))
    }

    func testPostingIsOnCompanySite_ignoresGenericTokens() {
        // "Tech Solutions" → both tokens generic → no confident match → false (button stays enabled).
        XCTAssertFalse(JobSearchLinks.postingIsOnCompanySite(
            company: "Tech Solutions", postingURL: "https://solutions.example.com/job/1"
        ))
    }

    func testPostingIsOnCompanySite_falseWhenMissingInputs() {
        XCTAssertFalse(JobSearchLinks.postingIsOnCompanySite(company: nil, postingURL: "https://x.com"))
        XCTAssertFalse(JobSearchLinks.postingIsOnCompanySite(company: "Google", postingURL: nil))
    }

    func testCompanyMatchTokens_dropsGenericAndShort() {
        XCTAssertEqual(JobSearchLinks.companyMatchTokens("Akamai Technologies"), ["akamai"])
        XCTAssertEqual(JobSearchLinks.companyMatchTokens("GitLab"), ["gitlab"])
    }
}
