import Foundation
import XCTest
@testable import JobhuntCore

/// JSON-LD carries the pay band as structured data, but only `description` and `jobLocationType` were
/// surfaced into the cleaned text — so a posting whose salary lives in markup (or whose visible salary
/// line the boilerplate stripper removes) reached the model with no pay information at all.
/// Job #581 (LiveKit) captured "$225K – $265K" and still extracted salary as null.
final class JsonLdSalaryTests: XCTestCase {
    private func posting(_ baseSalary: [String: Any]?) -> [[String: Any]] {
        var item: [String: Any] = ["@type": "JobPosting", "description": "We are hiring a Staff PM."]
        if let baseSalary { item["baseSalary"] = baseSalary }
        return [item]
    }

    private func cleaned(_ structured: [[String: Any]], visible: String = "Some page text.") -> String {
        cleanDescription(selectedText: "", visibleText: visible, structuredData: structured)
    }

    /// The reported case: a min/max band in markup must survive into the text the model reads.
    func testSalaryRangeIsSurfaced() {
        let text = cleaned(posting([
            "@type": "MonetaryAmount", "currency": "USD",
            "value": ["@type": "QuantitativeValue", "minValue": 225_000, "maxValue": 265_000, "unitText": "YEAR"]
        ]))
        XCTAssertTrue(text.contains("225000"), text)
        XCTAssertTrue(text.contains("265000"), text)
        XCTAssertTrue(text.contains("USD"), text)
        XCTAssertTrue(text.lowercased().contains("per year"), text)
    }

    /// schema.org permits the numbers as strings; both forms appear in the wild.
    func testStringEncodedAmountsAreAccepted() {
        let text = cleaned(posting([
            "currency": "USD",
            "value": ["minValue": "225000", "maxValue": "265000"]
        ]))
        XCTAssertTrue(text.contains("225000") && text.contains("265000"), text)
    }

    func testSingleValueSalaryIsSurfaced() {
        let text = cleaned(posting(["currency": "GBP", "value": ["value": 120_000]]))
        XCTAssertTrue(text.contains("120000"), text)
        XCTAssertTrue(text.contains("GBP"), text)
    }

    /// A band whose ends match reads as one figure, not "X–X".
    func testIdenticalMinAndMaxRenderOnce() {
        let text = cleaned(posting(["value": ["minValue": 200_000, "maxValue": 200_000]]))
        XCTAssertTrue(text.contains("200000"), text)
        XCTAssertFalse(text.contains("200000–200000"), text)
    }

    // MARK: - Must not invent a salary

    func testNoSalaryKeyAddsNothing() {
        let text = cleaned(posting(nil))
        XCTAssertFalse(text.lowercased().contains("base salary"), text)
    }

    func testZeroOrMissingAmountsAreIgnored() {
        XCTAssertFalse(cleaned(posting(["value": ["minValue": 0, "maxValue": 0]]))
            .lowercased().contains("base salary"))
        XCTAssertFalse(cleaned(posting(["value": [:] as [String: Any]]))
            .lowercased().contains("base salary"))
        XCTAssertFalse(cleaned(posting(["currency": "USD"])).lowercased().contains("base salary"))
    }

    func testGarbageAmountIsIgnoredRatherThanEmittedAsZero() {
        let text = cleaned(posting(["value": ["minValue": "competitive", "maxValue": "DOE"]]))
        XCTAssertFalse(text.lowercased().contains("base salary"), text)
    }

    /// The description must still come through — the salary line is additive, not a replacement.
    func testDescriptionIsStillIncluded() {
        let text = cleaned(posting(["value": ["minValue": 100_000, "maxValue": 150_000]]))
        XCTAssertTrue(text.contains("We are hiring a Staff PM."), text)
    }
}
