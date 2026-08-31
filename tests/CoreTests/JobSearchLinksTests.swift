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

/// The "find on company site" button must stay ENABLED on an aggregator, however much the URL slug
/// looks like the company's own site.
///
/// Reported on jobs #966 and #973: both are Glassdoor links whose path carries the company name, so
/// the whole-URL substring test read them as already-direct, disabled the button, and told the user
/// the posting "already looks like it's on Vanta's own site". An aggregator link is precisely where
/// finding the company's own posting is most worth doing.
final class AggregatorIsNotTheCompanySiteTests: XCTestCase {
    func testGlassdoorSlugCarryingTheCompanyNameIsNotTheCompanySite() {
        // Job #966, trimmed of its tracking query.
        XCTAssertFalse(JobSearchLinks.postingIsOnCompanySite(
            company: "Vanta",
            postingURL: "https://www.glassdoor.com/job-listing/staff-product-manager-ai-foundations-vanta-JV_KO0,36_KE37,42.htm"
        ))
        // Job #973.
        XCTAssertFalse(JobSearchLinks.postingIsOnCompanySite(
            company: "Syniti",
            postingURL: "https://www.glassdoor.com/job-listing/sr-manager-technical-program-syniti-JV_KO0,28_KE29,35.htm"
        ))
    }

    func testEveryExcludedAggregatorIsTreatedTheSameWay() {
        for domain in JobSearchLinks.excludedAggregatorDomains {
            XCTAssertFalse(
                JobSearchLinks.postingIsOnCompanySite(
                    company: "Acme", postingURL: "https://www.\(domain)/jobs/senior-pm-acme-123"
                ),
                "\(domain) puts the company name in the slug; it is still not the company's site"
            )
        }
    }

    /// The path match is deliberate and must survive — applying through a company's own ATS is direct,
    /// and that is the case the whole-URL test was written for.
    func testAnATSPathStillCountsAsTheCompanySite() {
        XCTAssertTrue(JobSearchLinks.postingIsOnCompanySite(
            company: "GitLab", postingURL: "https://boards.greenhouse.io/gitlab/jobs/1234"
        ))
        XCTAssertTrue(JobSearchLinks.postingIsOnCompanySite(
            company: "Vanta", postingURL: "https://www.vanta.com/careers/staff-product-manager"
        ))
    }

    /// Only the HOST decides. A company careers page that happens to mention an aggregator in its
    /// path is still the company's own site.
    func testAnAggregatorNamedInThePathDoesNotDisqualifyTheHost() {
        XCTAssertTrue(JobSearchLinks.postingIsOnCompanySite(
            company: "Acme", postingURL: "https://acme.com/careers/apply-via-linkedin.com/123"
        ))
    }

    /// Subdomains of an aggregator are aggregators; a lookalike domain is not.
    func testSubdomainMatchingIsAnchoredToTheDomainBoundary() {
        XCTAssertFalse(JobSearchLinks.postingIsOnCompanySite(
            company: "Acme", postingURL: "https://uk.indeed.com/viewjob?jk=acme123"
        ))
        XCTAssertTrue(JobSearchLinks.postingIsOnCompanySite(
            company: "Acme", postingURL: "https://notglassdoor.com/acme/jobs/1"
        ))
    }
}
