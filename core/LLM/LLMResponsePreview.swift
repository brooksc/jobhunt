import Foundation

/// What to keep of a model response that couldn't be parsed.
///
/// The stored preview was the first 2,000 characters — which, for a JSON parse failure, is the part
/// that parses *fine*. Job #861 (an Instacart posting) failed three identical extractions and left
/// three previews of immaculate JSON, because whatever broke it lay past character 2,000. The one
/// question the diagnostic exists to answer — *where does this stop being JSON?* — was the one thing
/// it threw away.
///
/// So keep both ends. The head still identifies the response, and the tail carries the answer: a
/// response cut off mid-array ends without its closing brackets, while a syntax error shows up as
/// whatever the model actually wrote there.
public enum LLMResponsePreview {
    /// Total characters kept, split between the two ends.
    public static let budget = LLMConstants.maxResponsePreviewChars
    /// Marks the elision, and states what was dropped so nobody reads the two halves as contiguous.
    static let elisionMarker = "\n…[%d characters omitted]…\n"

    public static func forUnparseableJSON(_ raw: String) -> String {
        guard raw.count > budget else { return raw }
        // The tail gets the larger share: a truncated or malformed response fails at its end, and the
        // head is mostly the same field list on every posting.
        let tailBudget = budget * 2 / 3
        let headBudget = budget - tailBudget
        let omitted = raw.count - headBudget - tailBudget
        return String(raw.prefix(headBudget))
            + String(format: elisionMarker, omitted)
            + String(raw.suffix(tailBudget))
    }
}
