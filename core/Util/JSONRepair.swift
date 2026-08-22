// JSONRepair.swift — minimal port of npm jsonrepair behavior
// Pure Foundation only — no SwiftUI/AppKit/SwiftData imports.

import Foundation

// MARK: - Public API

/// Extracts JSON from a string that may be wrapped in markdown fences (```json ... ```).
/// Returns the raw JSON string, or the original input if no fence found.
public func extractJSON(_ input: String) -> String {
    let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
    // Match ```json\n...\n``` or ``` ... ```
    if let match = trimmed.range(of: #"```(?:json)?\s*\n?([\s\S]*?)\n?\s*```"#, options: .regularExpression) {
        // Extract capture group 1
        let full = String(trimmed[match])
        // Strip the leading ```json or ``` and trailing ```
        let inner = full
            .replacingOccurrences(of: #"^```(?:json)?\s*\n?"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"\n?\s*```$"#, with: "", options: .regularExpression)
        return inner.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    return trimmed
}

/// Attempts to repair malformed JSON strings.
///
/// Handles:
/// - Markdown fences (```json ... ```)
/// - Trailing commas before `}` or `]`
/// - Unquoted object keys
/// - Single-quoted strings
/// - Missing quotes around string values (best-effort)
///
/// Returns repaired JSON string. Throws if the result still can't be parsed.
public func repairJSON(_ input: String) throws -> String {
    let extracted = extractJSON(input)

    // Never "repair" something that is already correct.
    //
    // Every step below ran unconditionally, and only then was the result validated — so a VALID
    // response could be mangled into an invalid one and reported as the model's fault. Job #861
    // failed ten times across two captures on this:
    //
    //     {"note": "CA, NY: $189,000—$199,500 USD; WA: $181,000"}
    //
    // Instacart's multi-state pay table. `quoteUnquotedKeys` sees `CA, NY:` INSIDE the string and
    // helpfully quotes it as if it were an object key. The response was perfect; the repair broke it.
    if parsesAsJSON(extracted) { return extracted }

    // Apply the repairs cumulatively, but stop at the first version that parses — so a step can only
    // ever run on text that is still broken, and can't undo what an earlier one already fixed.
    var text = extracted
    for step in [removeFencedMarkdown, convertSingleQuotes, quoteUnquotedKeys, removeTrailingCommas] {
        text = step(text)
        if parsesAsJSON(text) { return text }
    }

    // Last resort: scan for the first { or [ and last } or ] and extract that substring.
    // This handles prose before/after the JSON object that a text-mode model emits.
    if let extracted = extractBracketedSubstring(text) {
        let repaired = removeTrailingCommas(extracted)
        if let data = repaired.data(using: .utf8),
           (try? JSONSerialization.jsonObject(with: data)) != nil {
            return repaired
        }
    }

    throw JSONRepairError.unparseable(text)
}

/// Whether `text` is already valid JSON — the check that decides whether repairing is warranted
/// at all.
private func parsesAsJSON(_ text: String) -> Bool {
    guard let data = text.data(using: .utf8) else { return false }
    return (try? JSONSerialization.jsonObject(with: data)) != nil
}

/// What `JSONSerialization` says is wrong with `raw`, position included.
///
/// Deliberately only the parser's diagnostic — never the model's text — so a description that reaches
/// a log or the UI can't leak the posting's contents. Lives here, beside the parsing, so the two
/// error types that report a failed parse can say the same thing (TASK-676 #4).
public func jsonParserComplaint(_ raw: String) -> String {
    guard let data = raw.data(using: .utf8) else { return "response was not valid UTF-8" }
    do {
        _ = try JSONSerialization.jsonObject(with: data)
        return "the repair pass changed it in a way that still didn't parse"
    } catch let error as NSError {
        let detail = error.userInfo["NSDebugDescription"] as? String
        return (detail ?? error.localizedDescription).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

/// The one sentence both parse failures report, so a user comparing two failed jobs isn't left
/// wondering whether "Model response could not be parsed as valid JSON" and "LLM response could not
/// be parsed as JSON" were different problems. They never were (TASK-676 #4).
public func jsonParseFailureMessage(_ raw: String) -> String {
    "LLM response could not be parsed as JSON — \(jsonParserComplaint(raw))"
}

public enum JSONRepairError: Error, LocalizedError {
    case unparseable(String)

    public var errorDescription: String? {
        switch self {
        case let .unparseable(text): jsonParseFailureMessage(text)
        }
    }
}

// MARK: - Repair steps

/// Strip ``` fences (redundant with extractJSON but defensive)
private func removeFencedMarkdown(_ text: String) -> String {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    if trimmed.hasPrefix("```") {
        let stripped = trimmed
            .replacingOccurrences(of: #"^```(?:json)?\s*\n?"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"\n?\s*```\s*$"#, with: "", options: .regularExpression)
        return stripped.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    return trimmed
}

/// Remove trailing commas before `}` or `]`.
///
/// Handles patterns like: `, }`, `,\n}`, `,  ]`
private func removeTrailingCommas(_ text: String) -> String {
    text.replacingOccurrences(
        of: #",\s*([}\]])"#,
        with: "$1",
        options: .regularExpression
    )
}

/// Quote unquoted object keys.
///
/// Matches `key:` at the start of a value where key is an identifier
/// not already preceded by `"`.
///
/// e.g. `{name: "foo"}` → `{"name": "foo"}`
private func quoteUnquotedKeys(_ text: String) -> String {
    // Pattern: (after { or , and optional whitespace) an unquoted identifier followed by :
    text.replacingOccurrences(
        of: #"([{,]\s*)([A-Za-z_$][A-Za-z0-9_$]*)\s*:"#,
        with: #"$1"$2":"#,
        options: .regularExpression
    )
}

/// Scans for the first `{` or `[` and the last matching `}` or `]`, returning that substring.
/// Returns nil if no bracketed region is found or indices are in the wrong order.
private func extractBracketedSubstring(_ text: String) -> String? {
    let firstCurly = text.firstIndex(of: "{")
    let firstSquare = text.firstIndex(of: "[")

    // Determine which opener comes first
    let useObject: Bool
    switch (firstCurly, firstSquare) {
    case (.none, .none):
        return nil
    case (.some, .none):
        useObject = true
    case (.none, .some):
        useObject = false
    case let (.some(c), .some(s)):
        useObject = c < s
    }

    if useObject {
        guard let open = firstCurly, let close = text.lastIndex(of: "}"), open <= close else { return nil }
        return String(text[open ... close])
    } else {
        guard let open = firstSquare, let close = text.lastIndex(of: "]"), open <= close else { return nil }
        return String(text[open ... close])
    }
}

/// Convert single-quoted strings to double-quoted strings.
///
/// Handles `'value'` → `"value"`, preserving escaped quotes inside.
/// This is a best-effort implementation — doesn't handle all edge cases.
private func convertSingleQuotes(_ text: String) -> String {
    var result = ""
    var idx = text.startIndex
    var inDouble = false
    var inSingle = false

    while idx < text.endIndex {
        let charVal = text[idx]
        let next = text.index(after: idx)

        switch charVal {
        case "\\" where inDouble || inSingle:
            // Escaped character — pass through both chars
            result.append(charVal)
            if next < text.endIndex {
                result.append(text[next])
                idx = text.index(after: next)
            } else {
                idx = next
            }
            continue
        case "\"" where !inSingle:
            inDouble.toggle()
            result.append(charVal)
        case "'" where !inDouble:
            inSingle.toggle()
            // Replace with double quote
            result.append("\"")
        default:
            result.append(charVal)
        }
        idx = next
    }
    return result
}
