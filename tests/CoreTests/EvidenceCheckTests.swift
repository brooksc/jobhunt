import Foundation
import XCTest
@testable import JobhuntCore

/// 32% of quoted evidence spans across 415 real jobs appear in no résumé the user has ever had, and
/// 74% of those are lifted verbatim from the job's own posting. The cases below are taken from that
/// corpus rather than invented.
final class EvidenceCheckTests: XCTestCase {
    private let resume = "Led the LLM inference migration at Meta. Reduced API review cycle time from 92 to 5 days."
    private let posting = "You will apply sound business judgment to A/B Testing across LLMs, LRMs and agents."

    func testAQuoteFromTheResumeIsSupported() {
        let spans = EvidenceCheck.classify(
            evidence: "The résumé says 'Led the LLM inference migration at Meta'.",
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
            evidence: "Résumé says 'shipped Zune Marketplace'.",
            resumes: [resume, "Shipped Zune Marketplace at Microsoft."], posting: posting
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
        XCTAssertTrue(EvidenceCheck.quotedSpans(in: "Résumé says 'Led the LLM ... at Meta'.").isEmpty)
    }

    /// Typography must not decide the verdict.
    func testCurlyQuotesAndDashesFoldBeforeComparison() {
        let spans = EvidenceCheck.classify(
            evidence: "It says \u{201C}reduced API review cycle time from 92 to 5 days\u{201D}.",
            resumes: [resume], posting: posting
        )
        XCTAssertEqual(spans.map(\.support), [.supported])
    }

    func testUnsupportedReturnsOnlyTheProblems() {
        let spans = EvidenceCheck.unsupported(
            evidence: "Has 'Led the LLM inference migration at Meta' and 'sound business judgment'.",
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
