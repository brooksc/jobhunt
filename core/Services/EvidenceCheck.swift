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
        for (a, b) in [("\u{2019}", "'"), ("\u{2018}", "'"), ("\u{201C}", "\""), ("\u{201D}", "\""),
                       ("\u{2014}", "-"), ("\u{2013}", "-")] {
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
}
