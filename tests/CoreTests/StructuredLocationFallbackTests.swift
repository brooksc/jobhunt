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
