// swiftlint:disable line_length
// CleaningTests.swift — port of tests/unit/cleaning.test.js
import XCTest
@testable import JobhuntCore

final class CleaningTests: XCTestCase {
    func testSelectedTextOnlyReturnsSelectedText() {
        let result = cleanDescription(selectedText: "Selected portion", visibleText: "")
        XCTAssertEqual(result, "Selected portion")
    }

    func testVisibleTextOnlyReturnsVisibleText() {
        let result = cleanDescription(selectedText: "", visibleText: "Full page text")
        XCTAssertEqual(result, "Full page text")
    }

    func testBothPresentCombinesSelectedFirstThenVisible() {
        let result = cleanDescription(selectedText: "Selected portion", visibleText: "Full page text")
        XCTAssertTrue(result.contains("Selected portion"), "selected text included")
        XCTAssertTrue(result.contains("Full page text"), "visible text included")
        // Selected must come before visible
        let selectedRange = result.range(of: "Selected portion")!
        let visibleRange = result.range(of: "Full page text")!
        XCTAssertLessThan(selectedRange.lowerBound, visibleRange.lowerBound, "selected text appears first")
        XCTAssertTrue(result.contains("---"), "separator present")
    }

    func testBothPresentWithStructuredDataCombinesAll() {
        let result = cleanDescription(
            selectedText: "Selected",
            visibleText: "Visible",
            structuredData: [["@type": "JobPosting", "description": "Structured details"]]
        )
        XCTAssertTrue(result.contains("Selected"), "selected text included")
        XCTAssertTrue(result.contains("Visible"), "visible text included")
        XCTAssertTrue(result.contains("Structured details"), "structured data included")
        // Selected must come before visible
        let selectedRange = result.range(of: "Selected")!
        let visibleRange = result.range(of: "Visible")!
        XCTAssertLessThan(selectedRange.lowerBound, visibleRange.lowerBound, "selected text appears first")
    }

    func testFallsBackToVisibleTextWhenSelectedTextIsEmpty() {
        let result = cleanDescription(selectedText: "", visibleText: "Full page text")
        XCTAssertEqual(result, "Full page text")
    }

    func testUsesVisibleTextWhenNoStructuredDataPresent() {
        let result = cleanDescription(visibleText: "Job details here\nLocation: Seattle, WA")
        XCTAssertEqual(result, "Job details here\nLocation: Seattle, WA")
    }

    func testReturnsEmptyStringForNoInput() {
        let result = cleanDescription()
        XCTAssertEqual(result, "")
    }

    func testNormalizesInternalWhitespace() {
        let result = cleanDescription(visibleText: "hello   world\n\n\nfoo")
        XCTAssertFalse(result.contains("  "), "Should not contain double spaces")
        XCTAssertFalse(result.contains("\n\n\n"), "Should not contain triple newlines")
    }

    func testTrimsLeadingAndTrailingWhitespace() {
        let result = cleanDescription(visibleText: "  hello world  ")
        XCTAssertEqual(result, result.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    func testAppendsHTMLStrippedJsonLdDescriptionAfterVisibleText() {
        let result = cleanDescription(
            visibleText: "Job title\nAbout the role",
            structuredData: [[
                "@type": "JobPosting",
                "description": "<p>Full job description with <b>important details</b>.</p>"
            ]]
        )
        XCTAssertTrue(result.contains("About the role"), "visible text included")
        XCTAssertTrue(
            result.contains("Full job description with important details"),
            "JSON-LD description included without HTML tags"
        )
        XCTAssertFalse(result.contains("<"), "no HTML tags in output")
    }

    func testStripsHTMLEntitiesFromJsonLdDescription() {
        let result = cleanDescription(
            visibleText: "Visible",
            structuredData: [[
                "@type": "JobPosting",
                "description": "Pay: &lt;$100k &amp; $200k&gt; &quot;annually&quot;"
            ]]
        )
        XCTAssertTrue(result.contains("Pay: <$100k & $200k> \"annually\""))
    }

    func testConvertsBlockLevelHTMLTagsToNewlines() {
        let result = cleanDescription(
            visibleText: "Job title",
            structuredData: [[
                "@type": "JobPosting",
                "description": "<p><b>San Francisco Bay Area:</b></p>133,400 - 226,600 USD Annual<p><b>All Other US Locations:</b></p>116,000 - 197,000 USD Annual"
            ]]
        )
        XCTAssertTrue(result.contains("San Francisco Bay Area:"), "SF Bay Area label present")
        XCTAssertTrue(result.contains("All Other US Locations:"), "All Other US label present")
        XCTAssertTrue(result.contains("133,400 - 226,600 USD Annual"), "SF salary range present")
        XCTAssertTrue(result.contains("116,000 - 197,000 USD Annual"), "other salary range present")
        // Label and value must be on separate lines
        let lines = result.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        let sfLabelIdx = lines.firstIndex(of: "San Francisco Bay Area:")
        XCTAssertNotNil(sfLabelIdx, "SF label on its own line")
        if let idx = sfLabelIdx {
            XCTAssertTrue(lines.count > idx + 1 && lines[idx + 1].contains("133,400"), "SF salary on line after label")
        }
    }

    func testIncludesWorkdayJsonLdSalaryWhenAbsentFromVisibleText() {
        let result = cleanDescription(
            visibleText: "Technical Program Manager\nRemote - USA\nFull time",
            structuredData: [[
                "@type": "JobPosting",
                "description": "Job duties. San Francisco Bay Area: 133,400 - 226,600 USD Annual All Other US Locations: 116,000 - 197,000 USD Annual"
            ]]
        )
        XCTAssertTrue(result.contains("133,400 - 226,600 USD Annual"))
        XCTAssertTrue(result.contains("116,000 - 197,000 USD Annual"))
    }

    func testSkipsJsonLdEntriesWithoutDescriptionField() {
        let result = cleanDescription(
            visibleText: "Visible content",
            structuredData: [["@type": "JobPosting", "title": "Engineer"]]
        )
        XCTAssertEqual(result, "Visible content")
    }

    func testIgnoresNonJobPostingStructuredData() {
        let result = cleanDescription(
            visibleText: "Visible text",
            structuredData: [
                ["@type": "Organization", "name": "Acme Corp"],
                ["@type": "BreadcrumbList"]
            ]
        )
        XCTAssertEqual(result, "Visible text")
    }

    func testTraversesAtGraphToFindJobPosting() {
        let result = cleanDescription(
            visibleText: "Page content",
            structuredData: [[
                "@context": "https://schema.org",
                "@graph": [
                    ["@type": "JobPosting", "description": "Found via @graph traversal."],
                    ["@type": "BreadcrumbList", "itemListElement": [] as [Any]]
                ]
            ]]
        )
        XCTAssertTrue(result.contains("Found via @graph traversal"))
        XCTAssertTrue(result.contains("Page content"))
    }

    func testPrependsWorkArrangementRemoteWhenTelecommute() {
        let result = cleanDescription(
            visibleText: "Some visible content",
            structuredData: [[
                "@type": "JobPosting",
                "jobLocationType": "TELECOMMUTE",
                "description": "Job details here."
            ]]
        )
        XCTAssertTrue(result.contains("Work arrangement: Remote"), "remote line present")
        XCTAssertTrue(result.contains("Job details here"), "description still included")
    }

    func testIncludesJobLocationTypeRemoteLineEvenWithoutDescription() {
        let result = cleanDescription(
            visibleText: "Some visible content",
            structuredData: [["@type": "JobPosting", "jobLocationType": "TELECOMMUTE"]]
        )
        XCTAssertTrue(result.contains("Work arrangement: Remote"))
    }

    func testIncludesJobPostingDescriptionEvenWhenVisibleTextAlreadyHasContent() {
        let result = cleanDescription(
            visibleText: "Salary: 116K-227K Annually",
            structuredData: [[
                "@type": "JobPosting",
                "description": "San Francisco Bay Area: 133,400 - 226,600 USD Annual All Other US Locations: 116,000 - 197,000 USD Annual"
            ]]
        )
        XCTAssertTrue(result.contains("116K-227K Annually"), "visible text salary badge present")
        XCTAssertTrue(result.contains("San Francisco Bay Area:"), "JSON-LD band label present")
    }

    // MARK: - Source preference / dedupe / boilerplate (new behaviour)

    func testPrefersSubstantialJsonLdBodyOverNoisyVisibleText() {
        let body = String(repeating: "Build and operate large-scale data systems. ", count: 6) // ~264 chars
        let result = cleanDescription(
            visibleText: "Home\nJobs\nApply now\nNoise nav and footer chrome lives here",
            structuredData: [["@type": "JobPosting", "description": body]]
        )
        XCTAssertTrue(result.contains("Build and operate large-scale data systems"), "JSON-LD body used")
        XCTAssertFalse(
            result.contains("Noise nav and footer chrome lives here"),
            "noisy visible text is not used when JSON-LD is substantial"
        )
    }

    func testDoesNotDuplicateSelectionAlreadyInVisibleText() {
        let selected = "We are hiring a Senior Engineer to build our platform."
        let visible = "Header\n\(selected)\nMore details about the role and benefits package."
        let result = cleanDescription(selectedText: selected, visibleText: visible)
        let occurrences = result.components(separatedBy: "Senior Engineer to build our platform").count - 1
        XCTAssertEqual(occurrences, 1, "selection should not be stored twice")
        XCTAssertFalse(result.contains("---"), "no separator when the selection was deduped")
    }

    func testStripsCommonBoilerplateLines() {
        let visible = """
        Apply now
        We use cookies to improve your experience.
        The Role
        Lead the data platform team.
        © 2026 Acme Corp
        """
        let result = cleanDescription(visibleText: visible)
        XCTAssertTrue(result.contains("The Role"))
        XCTAssertTrue(result.contains("Lead the data platform team."))
        XCTAssertFalse(result.contains("Apply now"), "apply button stripped")
        XCTAssertFalse(result.contains("We use cookies"), "cookie banner stripped")
        XCTAssertFalse(result.contains("© 2026"), "copyright footer stripped")
    }
}

// swiftlint:enable line_length
