// Cleaning.swift — port of server/cleaning.js
// Pure Foundation only — no SwiftUI/AppKit/SwiftData imports.

import Foundation

/// Cleans a job description from capture inputs.
///
/// Mirrors cleaning.js `cleanDescription`.
public func cleanDescription(
    selectedText: String = "",
    visibleText: String = "",
    structuredData: [[String: Any]] = []
) -> String {
    let selected = selectedText.trimmingCharacters(in: .whitespaces)
    if !selected.isEmpty {
        return normalizeWhitespace(selected)
    }

    var parts: [String] = []
    let vt = visibleText.trimmingCharacters(in: .whitespaces)
    if !vt.isEmpty { parts.append(vt) }

    let jsonLdDesc = extractJsonLdDescription(structuredData)
    if !jsonLdDesc.isEmpty { parts.append(jsonLdDesc) }

    return normalizeWhitespace(parts.joined(separator: "\n\n"))
}

// MARK: - JSON-LD helpers

private func extractJsonLdDescription(_ structuredData: [[String: Any]]) -> String {
    for item in structuredData {
        guard let posting = findJobPosting(item) else { continue }
        var parts: [String] = []
        if let locType = posting["jobLocationType"] as? String, locType == "TELECOMMUTE" {
            parts.append("Work arrangement: Remote")
        }
        if let desc = posting["description"] as? String, !desc.trimmingCharacters(in: .whitespaces).isEmpty {
            parts.append(stripHtml(desc))
        }
        if !parts.isEmpty { return parts.joined(separator: "\n") }
    }
    return ""
}

private func findJobPosting(_ value: Any) -> [String: Any]? {
    if let array = value as? [Any] {
        for item in array {
            if let posting = findJobPosting(item) { return posting }
        }
        return nil
    }
    guard let dict = value as? [String: Any] else { return nil }

    if let graph = dict["@graph"] {
        if let posting = findJobPosting(graph) { return posting }
    }

    let typeValue = dict["@type"]
    var types: [String] = []
    if let t = typeValue as? String {
        types = [t]
    } else if let t = typeValue as? [String] {
        types = t
    }
    if types.contains("JobPosting") { return dict }

    return nil
}

// MARK: - HTML stripping

/// Strips HTML tags and decodes entities. Mirrors cleaning.js `stripHtml`.
func stripHtml(_ html: String) -> String {
    var plain = html
    // Block-level tags → newline
    plain = plain.replacingOccurrences(of: #"<br\s*/?>"#, with: "\n", options: .regularExpression)
    plain = plain.replacingOccurrences(of: #"</(p|div|li|tr|h[1-6])>"#, with: "\n", options: .regularExpression)
    // Strip remaining tags
    plain = plain.replacingOccurrences(of: #"<[^>]+>"#, with: "", options: .regularExpression)
    // Decode entities
    plain = plain
        .replacingOccurrences(of: "&amp;", with: "&")
        .replacingOccurrences(of: "&lt;", with: "<")
        .replacingOccurrences(of: "&gt;", with: ">")
        .replacingOccurrences(of: "&quot;", with: "\"")
        .replacingOccurrences(of: "&#39;", with: "'")
        .replacingOccurrences(of: "&nbsp;", with: " ")
    // Decimal numeric entities &#NNN;
    plain = decodeNumericEntities(plain)
    // Workday salary-band newline split: after "Annual" insert newline before next band label
    plain = splitWorkdaySalaryBands(plain)
    return plain
}

private func decodeNumericEntities(_ text: String) -> String {
    // Use NSString replacements to handle &#NNN; and &#xHHH; entities
    var result = text

    // Process all numeric entity matches and replace them
    func replaceEntities(pattern: String, extractor: (String) -> Int?) {
        guard let re = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { return }
        // Collect all matches first, then process in reverse order to preserve offsets
        let nsStr = result as NSString
        let allRange = NSRange(location: 0, length: nsStr.length)
        let matches = re.matches(in: result, range: allRange)
        for match in matches.reversed() {
            guard let captureRange = Range(match.range(at: 1), in: result) else { continue }
            let numStr = String(result[captureRange])
            guard let codePoint = extractor(numStr),
                  let scalar = Unicode.Scalar(codePoint) else { continue }
            let replacement = String(scalar)
            if let fullRange = Range(match.range, in: result) {
                result.replaceSubrange(fullRange, with: replacement)
            }
        }
    }

    replaceEntities(pattern: #"&#(\d+);"#) { Int($0) }
    replaceEntities(pattern: #"&#x([0-9a-fA-F]+);"#) { Int($0, radix: 16) }

    return result
}

/// Inserts newline between Workday-style salary bands after "Annual".
/// Mirrors the lookbehind regex in cleaning.js.
private func splitWorkdaySalaryBands(_ text: String) -> String {
    // Pattern: after "Annual", whitespace, followed by label: dollar range
    // JS: /(?<=Annual)\s+(?=[A-Z][^:\n]{0,80}?:\s*\d{2,3}(?:,\d{3})+\s*[-–—])/g
    // Swift doesn't support lookbehind with variable width in NSRegularExpression,
    // so we implement it manually.
    guard text.contains("Annual") else { return text }

    // Split on "Annual\s+" where what follows looks like a band label
    // We find "Annual" then check if the next non-whitespace content matches a band-label pattern
    let bandLabelPattern = try? NSRegularExpression(
        pattern: #"^[A-Z][^:\n]{0,80}?:\s*\d{2,3}(?:,\d{3})+\s*[-–—]"#
    )
    guard let bandLabelRe = bandLabelPattern else { return text }

    var result = ""
    var remaining = text[...]

    while !remaining.isEmpty {
        guard let annualRange = remaining.range(of: "Annual") else {
            result += remaining
            break
        }
        // Append everything up to and including "Annual"
        result += remaining[..<annualRange.upperBound]
        remaining = remaining[annualRange.upperBound...]

        // Check if remaining starts with whitespace followed by a band label
        let wsEnd = remaining.firstIndex(where: { !$0.isWhitespace }) ?? remaining.endIndex
        let afterWs = remaining[wsEnd...]
        let afterWsStr = String(afterWs)
        let nsRange = NSRange(afterWsStr.startIndex..., in: afterWsStr)
        if bandLabelRe.firstMatch(in: afterWsStr, range: nsRange) != nil {
            // Replace the whitespace with newline
            result += "\n"
            remaining = afterWs
        }
        // else: leave whitespace as-is and continue
    }

    return result
}

// MARK: - Whitespace normalization

/// Mirrors cleaning.js `normalizeWhitespace`.
func normalizeWhitespace(_ value: String) -> String {
    let lines = value.split(separator: "\n", omittingEmptySubsequences: false)
        .map { line -> String in
            // Collapse runs of spaces/tabs to single space, then trim
            let collapsed = line.replacingOccurrences(of: #"[ \t]+"#, with: " ", options: .regularExpression)
            return collapsed.trimmingCharacters(in: .init(charactersIn: " \t"))
        }
    let joined = lines.joined(separator: "\n")
    // Collapse 3+ consecutive newlines to 2
    let normalized = joined.replacingOccurrences(of: #"\n{3,}"#, with: "\n\n", options: .regularExpression)
    return normalized.trimmingCharacters(in: .whitespacesAndNewlines)
}
