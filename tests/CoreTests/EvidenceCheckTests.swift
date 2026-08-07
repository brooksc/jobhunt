import Foundation
import XCTest
@testable import JobhuntCore

/// 32% of quoted evidence spans across 415 real jobs appear in no résumé the user has ever had, and
/// 74% of those are lifted verbatim from the job's own posting. The cases below are taken from that
/// corpus rather than invented.
final class EvidenceCheckTests: XCTestCase {
    // Fabricated. This repo is public and the real résumé never enters it — the corpus figures
    // these cases come from were measured out-of-band.
    private let resume = "Led the search ranking migration at Northwind. Cut release lead time from 40 to 3 days."
    private let posting = "You will apply sound business judgment to A/B Testing across LLMs, LRMs and agents."

    func testAQuoteFromTheResumeIsSupported() {
        let spans = EvidenceCheck.classify(
            evidence: "The résumé says 'Led the search ranking migration at Northwind'.",
            resumes: [resume], posting: posting
        )
        XCTAssertEqual(spans.map(\.support), [.supported])
    }

    /// #569, the clean demonstration: every span is JD vocabulary presented as résumé content.
    func testAQuoteLiftedFromThePostingIsCaught() {
        let spans = EvidenceCheck.classify(
            evidence: "Candidate shows 'sound business judgment' and 'A/B Testing' experience.",
            resumes: [resume], posting: posting
        )
        XCTAssertEqual(spans.map(\.support), [.liftedFromPosting, .liftedFromPosting])
    }

    /// #200: a credential in neither document. The severe case — a factual claim about the user.
    func testAQuoteInNeitherDocumentIsInvented() {
        let spans = EvidenceCheck.classify(
            evidence: "Résumé lists 'Certification: Project Management Professional (PMP).'",
            resumes: [resume], posting: posting
        )
        XCTAssertEqual(spans.map(\.support), [.invented])
    }

    /// A quote from a superseded résumé is stale, not invented — the user really did write it.
    func testOlderResumesCount() {
        let spans = EvidenceCheck.classify(
            evidence: "Résumé says 'shipped the Contoso catalogue'.",
            resumes: [resume, "Shipped the Contoso catalogue at Fabrikam."], posting: posting
        )
        XCTAssertEqual(spans.map(\.support), [.supported])
    }

    /// Apostrophes inside words are not quote marks. Reading them as such was the largest source of
    /// bogus spans before the boundary guards went in.
    func testApostrophesInsideWordsAreNotQuotes() {
        XCTAssertTrue(EvidenceCheck.quotedSpans(in: "The résumé doesn't say it's relevant.").isEmpty)
    }

    /// An elided quote is the model telling us it abbreviated; a literal lookup would call a truthful
    /// quote fabricated.
    func testElidedQuotesAreSkipped() {
        XCTAssertTrue(EvidenceCheck.quotedSpans(in: "Résumé says 'Led the search ranking ... at Northwind'.").isEmpty)
    }

    /// Typography must not decide the verdict.
    func testCurlyQuotesAndDashesFoldBeforeComparison() {
        let spans = EvidenceCheck.classify(
            evidence: "It says \u{201C}cut release lead time from 40 to 3 days\u{201D}.",
            resumes: [resume], posting: posting
        )
        XCTAssertEqual(spans.map(\.support), [.supported])
    }

    func testUnsupportedReturnsOnlyTheProblems() {
        let spans = EvidenceCheck.unsupported(
            evidence: "Has 'Led the search ranking migration at Northwind' and 'sound business judgment'.",
            resumes: [resume], posting: posting
        )
        XCTAssertEqual(spans.count, 1)
        XCTAssertEqual(spans.first?.support, .liftedFromPosting)
    }

    /// No quotes at all is not a defect — the model simply summarised. The check must not manufacture
    /// a finding from an absence.
    func testEvidenceWithoutQuotesProducesNothing() {
        XCTAssertTrue(EvidenceCheck.unsupported(
            evidence: "The résumé demonstrates extensive relevant experience.",
            resumes: [resume], posting: posting
        ).isEmpty)
    }
}

/// The check marks; it never overrules. An earlier version demoted a credited verdict whose quotes
/// were in neither document — checked against the hand labels that rule fired 7 times across 20 jobs
/// and **6 of the 7 contradicted the labeller**, because an exact-substring test can't tell invention
/// from paraphrase. These tests pin the marking, and pin that verdicts survive it.
final class EvidenceCheckApplyTests: XCTestCase {
    private let resume = "Led the search ranking migration at Northwind."
    private let posting = "You will apply sound business judgment across LLMs and agents."

    private func assess(_ status: String, _ evidence: String) -> [[String: Any]] {
        [["requirement": "Experience with distributed systems", "kind": "required",
          "status": status, "evidence": evidence]]
    }

    private func apply(_ a: [[String: Any]]) -> EvidenceCheck.Applied {
        EvidenceCheck.apply(to: a, resumes: [resume], posting: posting)
    }

    /// The regression that matters: "Builder mentality" was demoted to `missing` on evidence the
    /// labeller had read and accepted. A verdict must survive being marked.
    func testAnInventedQuoteMarksButNeverChangesTheVerdict() {
        let result = apply(assess("met", "Résumé lists 'Certification: Project Management Professional'."))
        XCTAssertEqual(result.flagged, 1)
        XCTAssertEqual(result.assessments[0]["status"] as? String, "met")
        XCTAssertEqual(result.assessments[0][EvidenceCheck.supportKey] as? String, "invented")
    }

    func testAPartialIsAlsoLeftIntact() {
        let result = apply(assess("partial", "Résumé lists 'Certification: PMP credential'."))
        XCTAssertEqual(result.assessments[0]["status"] as? String, "partial")
        XCTAssertEqual(result.flagged, 1)
    }

    /// The two severities are still distinguished — they're worded differently to the user.
    func testAQuoteLiftedFromThePostingIsMarkedAsSuch() {
        let result = apply(assess("met", "Candidate shows 'sound business judgment'."))
        XCTAssertEqual(result.flagged, 1)
        XCTAssertEqual(result.assessments[0]["status"] as? String, "met")
        XCTAssertEqual(result.assessments[0][EvidenceCheck.supportKey] as? String, "liftedFromPosting")
    }

    /// One real quote clears the whole assessment: mixed evidence means the model did find something.
    func testOneSupportedQuoteClearsTheAssessment() {
        let result = apply(assess(
            "met", "Résumé says 'Led the search ranking migration at Northwind' and 'sound business judgment'."
        ))
        XCTAssertEqual(result.flagged, 0)
        XCTAssertNil(result.assessments[0][EvidenceCheck.supportKey])
    }

    /// Silence is not guilt. Penalising a model that summarises instead of quoting would punish
    /// exactly the behaviour that avoids this defect.
    func testAnAssessmentWithNoQuotesIsUntouched() {
        XCTAssertEqual(apply(assess("met", "The résumé demonstrates this clearly.")).flagged, 0)
    }

    /// Re-running must not compound: the migrator pass is expected to be run more than once.
    func testApplyingTwiceIsStable() {
        let once = apply(assess("met", "Résumé lists 'Certification: Project Management Professional'."))
        let twice = apply(once.assessments)
        XCTAssertEqual(twice.flagged, 1)
        XCTAssertEqual(twice.assessments[0]["status"] as? String, "met")
        XCTAssertEqual(twice.assessments[0][EvidenceCheck.supportKey] as? String, "invented")
    }

    func testTheOffendingQuotesArePreservedForTheUI() {
        let result = apply(assess("met", "Candidate shows 'sound business judgment'."))
        XCTAssertEqual(result.assessments[0][EvidenceCheck.unsupportedSpansKey] as? [String],
                       ["sound business judgment"])
    }
}
