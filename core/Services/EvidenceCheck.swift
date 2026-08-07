import Foundation

/// Whether the résumé actually says what a requirement assessment claims it says.
///
/// The scorer asks the model to quote its evidence, and the quotes are often not in the résumé:
/// **32% of quoted spans corpus-wide appear in no résumé the user has ever had**, across 44 of 415
/// jobs. That is not free hallucination — **74% of them are lifted verbatim from that job's own
/// posting**. The mechanism is visible in the prompt: the scoring rules demand a literal named
/// technology, the résumé doesn't contain one, and the nearest literal string is sitting right there
/// in the job description, so the model copies it and presents it as résumé text. Job #569 quotes
/// `LLMs, LRMs`, `A/B Testing` and `sound business judgment` — all straight from the JD.
///
/// The remaining quarter is free invention, and it is the more serious kind: #200 quoted
/// `Certification: Project Management Professional (PMP).` as résumé content. A credential the user
/// may not hold, driving a `met`.
///
/// Detection is deterministic and costs nothing per job — the two texts are already in hand at the
/// moment the analysis is written. This type only *classifies*; what a bad quote should do to the
/// verdict is a separate decision, because the two severities don't deserve the same treatment.
public enum EvidenceCheck {
    /// Where a quoted span actually came from.
    public enum Support: String, Sendable, Equatable {
        /// Found in a résumé the user has had. The normal case.
        case supported
        /// Found in the job posting but in no résumé — the model quoting the JD back at itself. A
        /// grounding failure; the conclusion may still be right.
        case liftedFromPosting
        /// In neither. A factual claim about the user that nothing supports.
        case invented
    }

    public struct Span: Sendable, Equatable {
        public let text: String
        public let support: Support
        public init(text: String, support: Support) {
            self.text = text
            self.support = support
        }
    }

    /// A quoted span. Deliberately not opened or closed mid-word, so `don't` and `it's` don't read as
    /// quote marks — that alone accounted for most of the false spans in the first pass.
    private static let quotePattern = """
    (?<![A-Za-z0-9])['\u{2018}]([^'\u{2018}\u{2019}\n]{4,120})['\u{2019}](?![A-Za-z])\
    |(?<![A-Za-z0-9])["\u{201C}]([^"\u{201C}\u{201D}\n]{4,120})["\u{201D}]
    """

    /// Fold typography and whitespace, so a quote isn't called fabricated over a curly apostrophe.
    public static func normalized(_ text: String) -> String {
        var s = text.folding(options: [.widthInsensitive], locale: nil)
        for (a, b) in [
            ("\u{2019}", "'"),
            ("\u{2018}", "'"),
            ("\u{201C}", "\""),
            ("\u{201D}", "\""),
            ("\u{2014}", "-"),
            ("\u{2013}", "-")
        ] {
            s = s.replacingOccurrences(of: a, with: b)
        }
        return s.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// The quoted spans worth checking. Anything elided with an ellipsis is skipped: the model is
    /// signalling it abbreviated, so a literal lookup would call a truthful quote fabricated.
    public static func quotedSpans(in evidence: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: quotePattern) else { return [] }
        let range = NSRange(evidence.startIndex ..< evidence.endIndex, in: evidence)
        return regex.matches(in: evidence, range: range).compactMap { match in
            for group in 1 ... 2 {
                guard let r = Range(match.range(at: group), in: evidence) else { continue }
                let span = String(evidence[r]).trimmingCharacters(in: .whitespacesAndNewlines)
                if span.contains("...") || span.contains("\u{2026}") { return nil }
                return span.count >= 5 ? span : nil
            }
            return nil
        }
    }

    /// Classify every quoted span in one assessment's evidence.
    ///
    /// `resumes` is every résumé the user has ever had active, not just the current one: a quote from
    /// a superseded version is a stale quote, not an invented one, and calling it invented would
    /// accuse the model of something it didn't do.
    public static func classify(evidence: String, resumes: [String], posting: String) -> [Span] {
        let haystacks = resumes.map(normalized)
        let jd = normalized(posting)
        return quotedSpans(in: evidence).map { span in
            let needle = normalized(span)
            if haystacks.contains(where: { $0.contains(needle) }) {
                return Span(text: span, support: .supported)
            }
            return Span(
                text: span,
                support: !jd.isEmpty && jd.contains(needle) ? .liftedFromPosting : .invented
            )
        }
    }

    /// Spans that no résumé supports. Empty means the evidence checks out — or that the model quoted
    /// nothing at all, which this check cannot distinguish and does not try to.
    public static func unsupported(evidence: String, resumes: [String], posting: String) -> [Span] {
        classify(evidence: evidence, resumes: resumes, posting: posting)
            .filter { $0.support != .supported }
    }

    /// Key under which the outcome is stamped into each stored assessment.
    public static let supportKey = "evidence_support"
    /// The offending quotes, kept so the UI can show *which* words aren't in the résumé rather than
    /// asking the user to take the warning on faith.
    public static let unsupportedSpansKey = "unsupported_evidence"

    public struct Applied: Sendable, Equatable {
        public let assessments: [[String: Any]]
        /// Verdicts marked as citing something the résumé doesn't say.
        public let flagged: Int

        public static func == (lhs: Applied, rhs: Applied) -> Bool {
            lhs.flagged == rhs.flagged
        }
    }

    /// Mark every assessment whose quoted evidence the résumé doesn't support.
    ///
    /// **Marks; never overrules.** An earlier version of this demoted a credited verdict to `missing`
    /// when its quotes appeared in neither document, on the reasoning that an invented credential
    /// (#200's PMP) makes the conclusion worthless. Checked against the hand labels, that rule fired
    /// 7 times across 20 jobs and **6 of the 7 contradicted the labeller, who had marked all six
    /// `met`.** The requirements it hit were "Builder mentality", "Excellent communication", "Strong
    /// product sense" — and the evidence for them was real résumé content lightly reworded or
    /// reassembled across lines, so an exact-substring test missed it.
    ///
    /// A substring check cannot tell **invention from paraphrase**, and paraphrase is by far the
    /// commoner of the two. So the check's job is to surface, not to decide. When a flagged row is
    /// genuinely wrong the user flags it "I don't have this", and `ScoringFeedback` demotes it
    /// deterministically and everywhere — machinery that already exists and that the user controls.
    ///
    /// **A single supported quote clears the whole assessment**, and an assessment that quotes
    /// nothing is left alone: a summary without quotes is not evidence of fabrication, and treating
    /// silence as guilt would penalise the models that abstain rather than invent.
    public static func apply(
        to assessments: [[String: Any]],
        resumes: [String],
        posting: String
    ) -> Applied {
        var flagged = 0
        let updated = assessments.map { item -> [String: Any] in
            var item = item
            let spans = classify(
                evidence: (item["evidence"] as? String) ?? "", resumes: resumes, posting: posting
            )
            guard !spans.isEmpty, !spans.contains(where: { $0.support == .supported }) else {
                return item
            }
            let invented = spans.contains { $0.support == .invented }
            item[supportKey] = invented ? Support.invented.rawValue : Support.liftedFromPosting.rawValue
            item[unsupportedSpansKey] = spans.map(\.text)
            flagged += 1
            return item
        }
        return Applied(assessments: updated, flagged: flagged)
    }
}
