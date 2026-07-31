import Foundation
import XCTest
@testable import JobhuntCore

/// A JSON-LD `description` of 200+ chars is promoted to the primary description and the visible text
/// is discarded wholesale — losing anything the structured body omits. Pay-transparency blurbs are the
/// common casualty: they're appended to the page separately from the posting body, so the JSON-LD ends
/// at the qualifications with `baseSalary` null. Microsoft #676 captured
/// "USD $142,800 - $274,800 per year" and threw it away; all four Microsoft jobs extracted salary-less.
final class SalaryRecoveryTests: XCTestCase {
    /// Long enough to be promoted over the visible text, and — like Microsoft's — silent on pay.
    private let jsonLdBody = String(repeating: "Responsibilities and qualifications prose. ", count: 8)

    private func posting(_ description: String) -> [[String: Any]] {
        [["@type": "JobPosting", "description": description]]
    }

    private func clean(visible: String, jsonLd: String? = nil) -> String {
        cleanDescription(
            selectedText: "", visibleText: visible, structuredData: posting(jsonLd ?? jsonLdBody)
        )
    }

    // MARK: - The reported case

    func testMicrosoftPayRangeSurvivesJSONLDPromotion() {
        let visible = """
        Qualifications ... product demos).#wss#ISEngineering
        Technical Program Management IC5 - The typical base pay range for this role across the U.S. \
        is USD $142,800 - $274,800 per year. There is a different range applicable to specific work \
        locations, within the San Francisco Bay area and New York City metropolitan area, and the \
        base pay range for this role in those locations is USD $188,000 - $304,200 per year.
        """
        let cleaned = clean(visible: visible)
        XCTAssertTrue(cleaned.contains("$142,800"), cleaned)
        XCTAssertTrue(cleaned.contains("$274,800"), cleaned)
    }

    /// An abbreviation must not split the sentence early — the recovered text would otherwise read
    /// "is USD $142,800 - $274,800 per year." with the "base pay range" context stripped off.
    func testAbbreviationDoesNotTruncateTheRecoveredSentence() {
        let visible = "Technical Program Management IC5 - The typical base pay range for this role "
            + "across the U.S. is USD $142,800 - $274,800 per year."
        let recovered = salarySentences(in: visible)
        XCTAssertEqual(recovered.count, 1, "\(recovered)")
        XCTAssertTrue(recovered[0].contains("base pay range"), recovered[0])
        XCTAssertTrue(recovered[0].contains("$142,800"), recovered[0])
    }

    func testSentencesStillSplitOnRealTerminators() {
        let two = "The base pay range is $100,000 - $150,000 per year. "
            + "The salary range in NYC is $180,000 - $220,000 per year."
        XCTAssertEqual(salarySentences(in: two).count, 2)
    }

    /// The real Microsoft shape: page sections are glued together with no spaces, so the pay
    /// statement sits inside a multi-thousand-character run. Discarding long runs threw it away.
    func testPayIsRecoveredFromAGluedRunOfText() {
        let filler = String(repeating: "Requirement text that runs on and on without a break. ", count: 20)
        let glued = filler + "product demos).#wss#ISEngineeringTechnical Program Management IC5 - The "
            + "typical base pay range for this role across the U.S. is USD $142,800 - $274,800 per year."
        let recovered = salarySentences(in: glued)
        XCTAssertEqual(recovered.count, 1, "\(recovered)")
        XCTAssertTrue(recovered[0].contains("$142,800"), recovered[0])
        XCTAssertTrue(recovered[0].contains("base pay range"), "context must survive: \(recovered[0])")
        XCTAssertLessThanOrEqual(recovered[0].count, 400, "must not append the whole run")
    }

    /// The location-specific band is a separate sentence and must not be dropped.
    func testSecondLocationBandIsAlsoRecovered() {
        let visible = "The typical base pay range is USD $142,800 - $274,800 per year. "
            + "The base pay range for this role in those locations is USD $188,000 - $304,200 per year."
        let cleaned = clean(visible: visible)
        XCTAssertTrue(cleaned.contains("$188,000"), cleaned)
        XCTAssertTrue(cleaned.contains("$304,200"), cleaned)
    }

    /// The structured body must still be the description — this is additive, not a replacement.
    func testJSONLDBodyIsStillThePrimaryDescription() {
        let cleaned = clean(visible: "Base pay range: $150,000 - $200,000 per year.")
        XCTAssertTrue(cleaned.contains("Responsibilities and qualifications prose."), cleaned)
    }

    func testNoDuplicationWhenTheJSONLDAlreadyStatesPay() {
        let body = jsonLdBody + " The base pay range for this role is $150,000 - $200,000 per year."
        let cleaned = clean(visible: "The base pay range for this role is $150,000 - $200,000 per year.", jsonLd: body)
        let occurrences = cleaned.components(separatedBy: "$150,000").count - 1
        XCTAssertEqual(occurrences, 1, cleaned)
    }

    /// Both Microsoft bands sit on ONE line: the first inside a huge glued run, the second after it.
    /// The windowed first band begins with qualifications text the JSON-LD also contains, which a
    /// prose-similarity containment check mistook for a duplicate and dropped.
    func testBothBandsSurviveWhenTheyShareALineWithTheJSONLDBody() {
        let visible = jsonLdBody
            + "product demos).#wss#ISEngineeringTechnical Program Management IC5 - The typical base pay "
            + "range for this role across the U.S. is USD $142,800 - $274,800 per year. There is a "
            + "different range applicable to specific work locations, within the San Francisco Bay area "
            + "and New York City metropolitan area, and the base pay range for this role in those "
            + "locations is USD $188,000 - $304,200 per year."
        let cleaned = clean(visible: visible)
        XCTAssertTrue(cleaned.contains("$142,800"), "first band lost: \(cleaned)")
        XCTAssertTrue(cleaned.contains("$188,000"), "second band lost: \(cleaned)")
    }

    // MARK: - Must not invent or drag in noise

    /// A bare currency amount is everywhere on a careers page; only an amount WITH a pay keyword counts.
    func testUnrelatedDollarAmountsAreNotTreatedAsPay() {
        for noise in [
            "We saved our customers $500 million last year.",
            "Our Series C raised $1,200,000 in funding.",
            "Join 10,000 employees at a $50,000,000 company."
        ] {
            XCTAssertTrue(salarySentences(in: noise).isEmpty, noise)
        }
    }

    /// …and a pay keyword with no figure is benefits prose, not a band.
    func testPayWordsWithoutAmountsAreIgnored() {
        XCTAssertTrue(salarySentences(in: "We offer a competitive base salary and equity.").isEmpty)
    }

    func testNothingIsAddedWhenThePageStatesNoPay() {
        let cleaned = clean(visible: "We are hiring. Great culture. Apply now.")
        XCTAssertFalse(cleaned.lowercased().contains("pay range"), cleaned)
    }

    // MARK: - The shapes real postings actually use

    /// Every one of these is a posting the user reported as showing no salary. They differ in ways
    /// the original matcher didn't allow for: a bare comma-grouped figure with no symbol at all, a
    /// "K" suffix, and a field labelled with nothing but the word "Compensation".
    func testRealWorldSalaryFormats() {
        let cases: [(String, String)] = [
            (
                "Microsoft — symbol + commas, mid-sentence",
                "The typical base pay range for this role across the U.S. is USD $142,800 - $274,800 per year."
            ),
            (
                "Twilio — no currency symbol, figures in a list under a lead-in",
                "The estimated pay ranges for this role are as follows: Based in Colorado: 188,240.00 - 235,300.00."
            ),
            (
                "Ashby — K suffix under a bare \"Compensation\" label",
                "Compensation $153K – $180K • Offers Equity"
            ),
            (
                "Lever — \"a year\" rather than \"per year\"",
                "The base salary is $220,000 - $240,000 a year."
            )
        ]
        for (label, text) in cases {
            XCTAssertEqual(salarySentences(in: text).count, 1, label)
        }
    }

    /// A lead-in sentence can announce the pay while the figures live in the bullets beneath it, so
    /// a bare number counts only in the couple of lines following such a lead-in.
    func testFiguresFollowingALeadInAreRecovered() {
        let text = "The estimated pay ranges for this role are as follows: "
            + "Based in Colorado, Hawaii or Illinois: 188,240.00 - 235,300.00. "
            + "Based in New York or California: 199,280.00 - 249,100.00."
        let found = salarySentences(in: text)
        XCTAssertFalse(found.isEmpty)
        XCTAssertTrue(found.joined().contains("188,240"), "\(found)")
    }

    /// A bare number with no pay lead-in anywhere near it must stay ignored, or every headcount and
    /// funding figure on the page becomes a salary.
    func testBareNumbersFarFromAnyPayContextAreIgnored() {
        XCTAssertTrue(salarySentences(in: "We have 10,000 employees across 25 offices.").isEmpty)
        XCTAssertTrue(salarySentences(in: "Founded in 2011. Over 1,500,000 customers served.").isEmpty)
    }

    // MARK: - salarySentences directly

    func testRecognisesCommonPayPhrasings() {
        for line in [
            "The salary range for this position is $180,000 - $220,000 per year.",
            "Compensation range: $95 - $120 per hour.",
            "Base salary: £90,000 per annum.",
            "This role pays $200,000 annually."
        ] {
            XCTAssertEqual(salarySentences(in: line).count, 1, line)
        }
    }

    /// Bounded so a runaway match can't append a wall of benefits text.
    func testAtMostThreeSentencesAreRecovered() {
        let many = (1 ... 8).map { "The base pay range is $\($0)00,000 - $\($0)50,000 per year." }
            .joined(separator: " ")
        XCTAssertEqual(salarySentences(in: many).count, 3)
    }

    func testIdenticalSentencesAreDeduped() {
        let repeated = "The base pay range is $100,000 - $150,000 per year. "
        XCTAssertEqual(salarySentences(in: repeated + repeated).count, 1)
    }

    func testEmptyTextYieldsNothing() {
        XCTAssertTrue(salarySentences(in: "").isEmpty)
    }
}
