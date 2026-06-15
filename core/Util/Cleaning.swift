// Cleaning.swift — port of server/cleaning.js
// Pure Foundation only — no SwiftUI/AppKit/SwiftData imports.

import Foundation

/// Minimum length for a JSON-LD posting body to be treated as the primary description.
private let jsonLdMinChars = 200

/// Cleans a job description from capture inputs.
///
/// Source preference, in order:
///   1. A substantial schema.org `JobPosting.description` (JSON-LD) — the canonical, boilerplate-
///      free posting body that most ATS emit.
///   2. The page's visible text, with common site chrome (nav/footer/cookie/apply) stripped.
/// The user's highlighted selection is prepended only when it isn't already contained in the
/// chosen body, so it is never stored twice.
public func cleanDescription(
    selectedText: String = "",
    visibleText: String = "",
    structuredData: [[String: Any]] = []
) -> String {
    let selected = selectedText.trimmingCharacters(in: .whitespaces)
    // Visible text is usually plain innerText, but some captures leak raw HTML markup and entities
    // (e.g. "<ul …>", "&amp;", "&nbsp;"). Strip serialized app-data blobs, then run the same HTML
    // strip/entity-decode used on the JSON-LD body, then drop site-chrome lines.
    let visible = stripBoilerplate(
        stripHtml(stripSerializedAppData(visibleText.trimmingCharacters(in: .whitespaces)))
    )
    let jsonLdDesc = extractJsonLdDescription(structuredData)

    // Promote a substantial JSON-LD body to the primary description; otherwise use the de-chromed
    // visible text (falling back to whatever JSON-LD exists if there's no visible text).
    let primary = jsonLdDesc.count >= jsonLdMinChars ? jsonLdDesc : (visible.isEmpty ? jsonLdDesc : visible)

    var parts: [String] = []
    let includeSelected = !selected.isEmpty && !isContained(selected, in: primary)
    if includeSelected { parts.append(selected) }
    if !primary.isEmpty {
        if includeSelected { parts.append("---") }
        parts.append(primary)
    }
    // When JSON-LD wasn't promoted to primary, still append it — it often carries salary bands or a
    // remote flag missing from the page text — unless that content is already present.
    if jsonLdDesc.count < jsonLdMinChars, !jsonLdDesc.isEmpty, !isContained(jsonLdDesc, in: primary) {
        parts.append(jsonLdDesc)
    }
    if parts.isEmpty { parts.append(selected) } // last resort: selection only

    return normalizeWhitespace(parts.joined(separator: "\n\n"))
}

// MARK: - Containment / dedupe

/// True when `inner` is already represented in `outer` (so it shouldn't be added again).
/// Compares whitespace/case-insensitively, with a partial-prefix fallback for near-matches.
private func isContained(_ inner: String, in outer: String) -> Bool {
    guard !outer.isEmpty else { return false }
    let needle = compactForCompare(inner)
    guard !needle.isEmpty else { return true }
    let haystack = compactForCompare(outer)
    if haystack.contains(needle) { return true }
    let probe = String(needle.prefix(80))
    return probe.count >= 40 && haystack.contains(probe)
}

private func compactForCompare(_ text: String) -> String {
    text.lowercased()
        .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        .trimmingCharacters(in: .whitespaces)
}

// MARK: - Boilerplate stripping

private let boilerplateExactLines: Set<String> = [
    "apply", "apply now", "easy apply", "quick apply", "apply for this job", "apply for this role",
    "save", "save job", "saved", "share", "share this job", "share this posting",
    "report job", "report this job", "report",
    "skip to content", "skip to main content", "back to search results", "back to jobs",
    "view all jobs", "see all jobs", "all jobs", "browse jobs", "search jobs",
    "sign in", "log in", "login", "sign up", "create account", "register",
    "related jobs", "similar jobs", "recommended jobs", "more jobs like this", "jobs you may like",
    "accept all cookies", "accept all", "accept cookies", "reject all", "decline", "got it",
    "manage cookies", "cookie preferences", "cookie settings", "cookie policy",
    "print", "print job", "email", "email job", "copy link", "follow", "following", "menu"
]

/// Removes common site-chrome lines (nav, footer, cookie/consent, apply/share buttons) from plain
/// page text. Deliberately conservative — only drops lines that strongly match known boilerplate —
/// to avoid cutting real description content.
func stripBoilerplate(_ text: String) -> String {
    guard !text.isEmpty else { return text }
    let kept = text.split(separator: "\n", omittingEmptySubsequences: false)
        .filter { !isBoilerplateLine(String($0)) }
    return kept.joined(separator: "\n")
}

private func isBoilerplateLine(_ rawLine: String) -> Bool {
    let line = rawLine.trimmingCharacters(in: .whitespaces)
    guard !line.isEmpty else { return false } // keep blank lines (paragraph breaks)
    let lower = line.lowercased()
    if boilerplateExactLines.contains(lower) { return true }
    if lower.contains("we use cookies") || lower.contains("uses cookies")
        || lower.contains("this site uses cookies")
        || (lower.contains("cookies") && lower.contains("by clicking")) {
        return true
    }
    if line.hasPrefix("©") || lower.hasPrefix("copyright ") { return true }
    return false
}

// MARK: - Serialized app-data stripping

/// Pages built with React/Next.js (and similar SSR frameworks) often expose their RSC/Flight
/// hydration payload or other serialized app state as page text. It captures as a huge minified blob
/// — `0:{…}` / `12:[…]` Flight chunks, `$undefined`, `_next/static`, `dangerouslySetInnerHTML` — that
/// is not part of the job description. Drop the lines that are clearly such serialized data, then
/// trim any separator/blank lines left dangling once a trailing blob is removed.
func stripSerializedAppData(_ text: String) -> String {
    guard !text.isEmpty else { return text }
    var kept = text.split(separator: "\n", omittingEmptySubsequences: false)
        .filter { !isSerializedDataLine(String($0)) }
    while let last = kept.last {
        let trimmed = last.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty || trimmed.allSatisfy({ $0 == "-" }) { kept.removeLast() } else { break }
    }
    return kept.joined(separator: "\n")
}

private func isSerializedDataLine(_ rawLine: String) -> Bool {
    let line = rawLine.trimmingCharacters(in: .whitespaces)
    guard line.count >= 80 else { return false } // never touch short prose lines
    // Next.js RSC/Flight chunk: a line beginning "<digits>:{" or "<digits>:[".
    if line.range(of: #"^\d+:[\[{]"#, options: .regularExpression) != nil { return true }
    // Strong framework markers anywhere on a long line.
    if line.contains("self.__next_f") || line.contains("_next/static/")
        || line.contains("dangerouslySetInnerHTML") { return true }
    // Long, brace/quote-dense line = minified serialized data, not prose.
    if line.count >= 300 {
        let structural = line.unicodeScalars.reduce(0) { acc, scalar in
            "{}[]\":,$".unicodeScalars.contains(scalar) ? acc + 1 : acc
        }
        if Double(structural) / Double(line.count) > 0.18 { return true }
    }
    return false
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
    if let typeStr = typeValue as? String {
        types = [typeStr]
    } else if let typeArr = typeValue as? [String] {
        types = typeArr
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

    /// Process all numeric entity matches and replace them
    func replaceEntities(pattern: String, extractor: (String) -> Int?) {
        guard let entityRegex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { return }
        // Collect all matches first, then process in reverse order to preserve offsets
        let nsStr = result as NSString
        let allRange = NSRange(location: 0, length: nsStr.length)
        let matches = entityRegex.matches(in: result, range: allRange)
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

/// Removes invisible / junk characters that leak from page text and render as odd gaps or joined
/// words: maps no-break and other unusual spaces to a normal space, the non-breaking hyphen to
/// `-`, and drops zero-width characters, variation selectors, and other control / format /
/// private-use code points. Legitimate content (smart quotes, em/en dashes, emoji) is preserved.
func scrubInvisibleCharacters(_ value: String) -> String {
    var scalars = String.UnicodeScalarView()
    scalars.reserveCapacity(value.unicodeScalars.count)
    for scalar in value.unicodeScalars {
        switch scalar.value {
        case 0x2011: // non-breaking hyphen → plain hyphen
            scalars.append("-")
        case 0xFE00 ... 0xFE0F: // variation selectors (category Mn — keep emoji, drop the selector)
            continue
        default:
            switch scalar.properties.generalCategory {
            case .spaceSeparator: // NBSP, narrow NBSP, en/em/thin spaces, ideographic space, …
                scalars.append(" ")
            case .format, .privateUse: // zero-width chars, BOM, soft hyphen, PUA font-icon leftovers
                continue
            case .control:
                if scalar == "\n" || scalar == "\t" { scalars.append(scalar) } // drop other controls (\r, …)
            default:
                scalars.append(scalar)
            }
        }
    }
    return String(scalars)
}

/// Mirrors cleaning.js `normalizeWhitespace`.
func normalizeWhitespace(_ rawValue: String) -> String {
    let value = scrubInvisibleCharacters(rawValue)
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
