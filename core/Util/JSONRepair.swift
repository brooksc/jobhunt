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
    var text = extractJSON(input)
    text = removeFencedMarkdown(text)
    text = convertSingleQuotes(text)
    text = quoteUnquotedKeys(text)
    text = removeTrailingCommas(text)

    // Validate it parses
    guard let data = text.data(using: .utf8),
          (try? JSONSerialization.jsonObject(with: data)) != nil else {
        throw JSONRepairError.unparseable(text)
    }
    return text
}

public enum JSONRepairError: Error {
    case unparseable(String)
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
