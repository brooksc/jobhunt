import Foundation
import XCTest
@testable import JobhuntCore

/// Structured-data location is a FALLBACK, not an override (TASK-675).
///
/// Netflix's board publishes jobLocation "Panamá, Provincia de Panamá, PA" — an upstream geocoding
/// artifact, verified live against their site — for a posting whose own page says "USA - Remote" five
/// times. The injected `Location:` line outweighed the page, job #961 stored as Panamá with
/// remoteType unknown, and LocationCriteria then dropped a $290k US-remote role out of criteria.
final class StructuredLocationFallbackTests: XCTestCase {
    private func netflixStructuredData() -> [[String: Any]] {
        [[
            "@type": "JobPosting",
            "title": "Technical Program Manager - Hawkins Design System",
            "jobLocation": [
                "@type": "Place",
                "address": [
                    "@type": "PostalAddress",
                    "addressCountry": ["@type": "Country", "name": "PA"],
                    "addressLocality": "Panamá",
                    "addressRegion": "Provincia de Panamá,PA"
                ] as [String: Any]
            ] as [String: Any]
        ]]
    }

    /// The regression: a page that states its own location must not be overruled by metadata.
    func testPageThatNamesItsLocationIsNotOverruledByMetadata() {
        let cleaned = cleanDescription(
            visibleText: """
            Technical Program Manager - Hawkins Design System
            USA - Remote
            Hawkins is Netflix's design system. We are looking for a Technical Program Manager to
            drive large, cross-team programs. USA - Remote.
            """,
            structuredData: netflixStructuredData()
        )
        XCTAssertFalse(
            cleaned.localizedCaseInsensitiveContains("Panam"),
            "the page says USA - Remote; its metadata must not inject a contradicting location:\n\(cleaned)"
        )
        XCTAssertTrue(cleaned.localizedCaseInsensitiveContains("USA - Remote"))
    }

    /// Job #961's real shape: a JSON-LD description long enough to be PROMOTED over the page text,
    /// which is where the "USA - Remote" actually is. Checking only the assembled body missed it and
    /// still injected Panamá — the first fix passed its own tests and left the real job broken.
    func testPageTextCountsEvenWhenTheJSONLDBodyIsPromoted() {
        let longBody = String(repeating: "We are hiring a program manager to drive programs. ", count: 40)
        let cleaned = cleanDescription(
            visibleText: "Technical Program Manager - Hawkins Design System\nUSA - Remote\n" + longBody,
            structuredData: [[
                "@type": "JobPosting",
                "description": longBody,
                "jobLocation": [
                    "@type": "Place",
                    "address": [
                        "@type": "PostalAddress",
                        "addressCountry": ["@type": "Country", "name": "PA"],
                        "addressLocality": "Panamá"
                    ] as [String: Any]
                ] as [String: Any]
            ]]
        )
        XCTAssertFalse(
            cleaned.localizedCaseInsensitiveContains("Panam"),
            "the page says USA - Remote; promoting the JSON-LD body must not lose that:\n\(cleaned)"
        )
    }

    /// Suppressing the metadata is only half the job. #961's JSON-LD body is promoted over the page
    /// text, so with the bogus Panamá line merely removed the posting had NO location at all — which
    /// LocationCriteria reads as on-site, and the job still failed the user's criteria. The page said
    /// "USA - Remote" the whole time.
    func testThePagesOwnLocationSurvivesAPromotedJSONLDBody() {
        let longBody = String(repeating: "We are hiring a program manager to drive programs. ", count: 40)
        let cleaned = cleanDescription(
            visibleText: "Technical Program Manager - Hawkins Design System USA - Remote Engineering Operations",
            structuredData: [[
                "@type": "JobPosting",
                "description": longBody,
                "jobLocation": [
                    "@type": "Place",
                    "address": ["@type": "PostalAddress", "addressLocality": "Panamá"] as [String: Any]
                ] as [String: Any]
            ]]
        )
        XCTAssertFalse(cleaned.localizedCaseInsensitiveContains("Panam"), cleaned)
        XCTAssertTrue(
            cleaned.localizedCaseInsensitiveContains("USA - Remote"),
            "the page's own location must reach the model, not just be absent:\n\(cleaned)"
        )
    }

    // MARK: - The phrase extractor

    func testPageLocationPhrasePrefersTheMostSpecificForm() {
        XCTAssertEqual(pageLocationPhrase("Title USA - Remote Engineering"), "USA - Remote")
        XCTAssertEqual(pageLocationPhrase("Remote - United States, full time"), "Remote - United States")
        XCTAssertEqual(pageLocationPhrase("Based in Los Gatos, California today"), "Los Gatos, California")
        XCTAssertEqual(pageLocationPhrase("This role is fully remote."), "fully remote")
        XCTAssertNil(pageLocationPhrase("We build systems and collaborate on delivery."))
        XCTAssertNil(pageLocationPhrase(""))
    }

    /// The case the injection was written for still works: Reddit #7944159's description named no
    /// location at all, and the JSON-LD was the only source.
    func testSilentPageStillGetsTheStructuredLocation() {
        let cleaned = cleanDescription(
            visibleText: """
            We are hiring an engineer to work on our ads platform. You will build systems and
            collaborate with partner teams on delivery.
            """,
            structuredData: [[
                "@type": "JobPosting",
                "jobLocation": [
                    "@type": "Place",
                    "address": ["@type": "PostalAddress", "addressLocality": "Remote - United States"] as [String: Any]
                ] as [String: Any]
            ]]
        )
        XCTAssertTrue(
            cleaned.localizedCaseInsensitiveContains("Remote - United States"),
            "a page with no location of its own still needs the metadata:\n\(cleaned)"
        )
    }

    /// When it does speak, it says what it is — a bare "Location:" reads as fact.
    func testInjectedLineIsLabelledAsMetadata() {
        let cleaned = cleanDescription(
            visibleText: "We are hiring an engineer to build systems with partner teams.",
            structuredData: [[
                "@type": "JobPosting",
                "jobLocation": [
                    "@type": "Place",
                    "address": ["@type": "PostalAddress", "addressLocality": "Dublin"] as [String: Any]
                ] as [String: Any]
            ]]
        )
        XCTAssertTrue(cleaned.contains("(from page metadata)"), cleaned)
    }

    // MARK: - The discriminator

    /// Ordinary prose must not read as a place. Job #961's body contains "Design Platform,
    /// Engineering", which a bare `Word, Capitalised` pattern matched — so the cleaner believed the
    /// posting stated its location, suppressed both the metadata line and the page's own, and left
    /// the job with no location at all. Two "fixes" passed their tests with this still broken.
    func testProseWithACommaIsNotALocation() {
        for prose in [
            "Design Platform, Engineering",
            "You will partner with Analytics, Engineering and Design",
            "Hawkins, Netflix's design system"
        ] {
            XCTAssertFalse(textNamesALocation(prose), "must not read as a place: \(prose)")
            XCTAssertNil(pageLocationPhrase(prose), "must not yield a phrase: \(prose)")
        }
    }

    /// Real places still match — the region half is a code or a spelled-out country.
    func testRealCityRegionPairsStillMatch() {
        for place in ["Los Gatos, CA", "Austin, TX", "London, United Kingdom", "Toronto, Canada"] {
            XCTAssertTrue(textNamesALocation(place), "must read as a place: \(place)")
        }
    }

    func testTextNamesALocation() {
        XCTAssertTrue(textNamesALocation("USA - Remote"))
        XCTAssertTrue(textNamesALocation("This role is fully remote."))
        XCTAssertTrue(textNamesALocation("Based in Los Gatos, California."))
        XCTAssertTrue(textNamesALocation("Austin, TX"))
        XCTAssertTrue(textNamesALocation("London, United Kingdom"))

        XCTAssertFalse(textNamesALocation(""))
        XCTAssertFalse(
            textNamesALocation("We build systems and collaborate with partner teams on delivery."),
            "ordinary prose must not read as a location, or the fallback never fires"
        )
    }
}
