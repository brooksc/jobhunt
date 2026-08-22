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
    // The structured data's OWN location fields, which nothing else reads. `extractJsonLdDescription`
    // takes only `description`, and schema.org keeps the location beside it in `jobLocation` /
    // `jobLocationType` — so a board whose description never names a city (most of them) reached the
    // model with no location at all and extracted as `unknown`, which the criteria check then treats
    // as on-site. Reddit #7944159 published `addressLocality: "Remote - United States"` in JSON-LD
    // while the promoted description said nothing; the job read as not-remote.
    //
    // Emitted whether or not JSON-LD was promoted: it is authoritative, structured, and cheap.
    //
    // FALLBACK, not override (TASK-675). This was appended whenever JSON-LD had it, on the assumption
    // that structured data is the better source. It isn't always: Netflix's board publishes
    // `jobLocation` "Panamá, Provincia de Panamá, PA" — an upstream geocoding artifact, verified live
    // against their site — for a posting whose own page says "USA - Remote" five times. One injected
    // `Location:` line outweighed that, the job stored as Panamá with remoteType unknown, and
    // `LocationCriteria` then dropped a $290k US-remote role out of the user's criteria entirely.
    //
    // So it only speaks when the text is silent, which is the case it was written for: Reddit
    // #7944159's description named no location at all.
    let bodySoFar = parts.joined(separator: "\n")
    // The VISIBLE text counts even when it isn't part of the assembled body. A substantial JSON-LD
    // description is promoted to primary and the page text is dropped — which is exactly what job
    // #961 does: its page says "USA - Remote" five times, its JSON-LD body never mentions location,
    // and checking only the assembled body therefore still injected the bogus Panamá line. The
    // question is whether the POSTING says where it is, not whether this particular assembly kept it.
    let visibleLocation = pageLocationPhrase(visible)
    let bodyHasLocation = textNamesALocation(bodySoFar)

    // Carry the page's own answer across, rather than merely suppressing the metadata's wrong one.
    // Suppression alone left #961 with NO location at all — which `LocationCriteria` reads as
    // on-site, so the job still failed the user's criteria. Removing a false answer is only half the
    // job; the true one was on the page the whole time.
    if !bodyHasLocation, let visibleLocation {
        parts.append("Location (from page text): \(visibleLocation)")
    }
    for entry in structuredLocationLines(structuredData) {
        // The deferral applies to `jobLocation` — the "where is this job" CLAIM, which can simply be
        // wrong — and never to `applicantLocationRequirements`, which says who may take the role.
        // That one only ever narrows: "remote, but only from Portugal" is not contradicted by a page
        // that says "remote", it is qualified by it, and nothing else in the capture states it.
        if entry.isPlacementClaim, bodyHasLocation || visibleLocation != nil { continue }
        // Judge duplication on the VALUE, not the label we add: the body states "Remote - United
        // States" as prose, never "Location: Remote - United States", so matching the labelled form
        // never fires and the line is appended a second time.
        guard !bodySoFar.localizedCaseInsensitiveContains(entry.value) else { continue }
        // Labelled as what it is. A bare "Location:" reads as fact; this one is a claim made by the
        // page's metadata, which is sometimes wrong.
        parts.append("\(entry.label) (from page metadata): \(entry.value)")
    }
    // When JSON-LD wasn't promoted to primary, still append it — it often carries salary bands or a
    // remote flag missing from the page text — unless that content is already present.
    if jsonLdDesc.count < jsonLdMinChars, !jsonLdDesc.isEmpty, !isContained(jsonLdDesc, in: primary) {
        parts.append(jsonLdDesc)
    }
    // Promoting JSON-LD discards the visible text wholesale, which loses anything the structured
    // description omits. Pay-transparency blurbs are the common casualty: they're appended to the
    // page separately from the posting body, so a JSON-LD `description` routinely ends at the
    // qualifications with `baseSalary` null (Microsoft #676 — "USD $142,800 - $274,800 per year" was
    // captured and then thrown away). Recover just the pay sentences rather than re-appending the
    // whole page, which would drag the site chrome back in.
    if jsonLdDesc.count >= jsonLdMinChars, !visible.isEmpty {
        // The same promotion also discards the page's metadata card, which is where some boards
        // state the work arrangement. Microsoft #675 captured "Work site 0 days / week in-office –
        // remote" and reached the model with nothing, so it extracted as unknown and read as
        // on-site (its JSON-LD says nothing about remote either).
        for phrase in workArrangementSentences(in: visible) {
            // Compare on the phrase, not the labelled line we emit — the body states it unlabelled.
            guard !parts.joined(separator: "\n").localizedCaseInsensitiveContains(phrase) else { continue }
            parts.append("Work site: \(phrase)")
        }
        for line in salarySentences(in: visible) {
            // Judge duplication on the AMOUNTS, not the surrounding prose. `isContained`'s 80-char
            // prefix probe compares the start of the excerpt, which for a windowed statement is
            // qualifications text the JSON-LD also contains — so a real pay band read as "already
            // present" and was dropped (Microsoft #676's first band).
            let amounts = moneyAmounts(in: line)
            let body = parts.joined(separator: "\n")
            if !amounts.isEmpty, amounts.allSatisfy({ body.contains($0) }) { continue }
            parts.append(line)
        }
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

// MARK: - Work-arrangement recovery from visible text

/// Statements of the work arrangement that a structured description omitted.
///
/// Boards that render a metadata card ("Work site: 0 days / week in-office – remote") state the
/// arrangement there rather than in the posting body, so promoting the JSON-LD description drops it
/// entirely and the job extracts as "unknown" — which the criteria check then treats as on-site.
func workArrangementSentences(in text: String) -> [String] {
    // The days-in-office count is the informative part — it states the arrangement even when the
    // word "remote" never appears ("3 days / week in-office"). The optional trailing word picks up
    // Microsoft's "– remote" without running on into the next card field ("Travel …").
    let pattern = #"(?i)\d+\s*days?\s*/?\s*week\s+in[- ]office(?:\s*[–—-]\s*[a-z]+)?"#
    guard let range = text.range(of: pattern, options: .regularExpression) else { return [] }
    return [String(text[range]).trimmingCharacters(in: .whitespaces)]
}

// MARK: - Salary recovery from visible text

/// Sentences in `text` that state pay, for re-adding when the structured description omitted it.
///
/// Requires BOTH a currency amount and a pay keyword: a bare "$" is far too common on a careers page
/// ("$1B in revenue", "save customers $500") and a bare "salary" often appears in benefits prose with
/// no figure. Both together is a reliable pay statement.
///
/// Capped at three sentences — enough for a base range plus a location-specific variant (Microsoft
/// states a separate SF/NYC band) without pulling in a benefits essay.
func salarySentences(in text: String) -> [String] {
    guard text.range(of: moneyPattern, options: .regularExpression) != nil else { return [] }

    // Bare "salary"/"compensation" are included: an amount is required alongside, so "competitive
    // salary" (no figure) and "$1.2M in funding" (no keyword) are both still rejected. Ashby labels
    // the field with nothing but the word "Compensation".
    let payKeyword = #"(?i)\b(salary|salaries|compensation|base pay|pay ranges?|pay scale|"#
        + #"estimated pay|typical pay|per year|per hour|per annum|annually|a year|an hour|"#
        + #"hourly rate|remuneration)\b"#
    var found: [String] = []
    var seen = Set<String>()
    // Sentences remaining in which a bare amount still counts as pay, set by a lead-in like
    // "The estimated pay ranges for this role are as follows:" whose figures live in the bullets
    // that follow rather than in the sentence itself (Twilio #8067440).
    var carryOver = 0

    // innerText collapses the page into few newlines, so split on sentence ends as well as lines.
    for raw in text.components(separatedBy: CharacterSet(charactersIn: "\n")) {
        for sentence in splitIntoSentences(raw) {
            let trimmed = sentence.trimmingCharacters(in: .whitespaces)
            let hasKeyword = trimmed.range(of: payKeyword, options: .regularExpression) != nil
            guard let money = trimmed.range(of: moneyPattern, options: .regularExpression) else {
                // A lead-in announcing pay makes the next couple of numeric lines count.
                if hasKeyword { carryOver = 2 }
                continue
            }
            guard trimmed.count >= 12 else { continue }
            guard hasKeyword || carryOver > 0 else { continue }
            if !hasKeyword { carryOver -= 1 }
            // Pages glue sections together without spaces ("…product demos).#wss#ISEngineeringTechnical
            // Program Management IC5 - The typical base pay range…"), so a "sentence" can run for
            // thousands of characters. Discarding it would throw away the pay statement it contains;
            // take a window around the amount instead.
            let statement = trimmed.count <= maxPaySentenceChars
                ? trimmed
                : payWindow(in: trimmed, around: money)
            let key = compactForCompare(statement)
            if seen.contains(key) { continue }
            seen.insert(key)
            found.append(statement)
            if found.count == 3 { return found }
        }
    }
    return found
}

/// A salary figure, in the three shapes postings actually use:
///   - with a currency symbol, commas optional, "K"/"M" allowed — `$95`, `$142,800`, `$153K` (Ashby)
///   - bare but comma-grouped — `188,240.00` (Twilio states ranges with no symbol at all)
/// A bare number without commas is deliberately NOT a match: it would hit every year and headcount
/// on the page. Callers pair this with a pay keyword, so a stray "10,000" can't be read as salary.
let moneyPattern = #"(?:[$€£]\s?\d{1,3}(?:,\d{3})*(?:\.\d{1,2})?\s?[KkMm]?|\d{1,3}(?:,\d{3})+(?:\.\d{2})?)"#

/// The currency amounts appearing in `text`, e.g. ["$142,800", "$274,800"].
func moneyAmounts(in text: String) -> [String] {
    let pattern = moneyPattern
    var amounts: [String] = []
    var searchStart = text.startIndex
    while let found = text.range(of: pattern, options: .regularExpression, range: searchStart ..< text.endIndex) {
        amounts.append(String(text[found]))
        searchStart = found.upperBound
    }
    return amounts
}

/// Longest pay statement kept verbatim; beyond this a window around the amount is taken instead.
private let maxPaySentenceChars = 400

/// A readable excerpt around a pay amount, for when the surrounding "sentence" is really a run of
/// glued-together page sections. Reaches back far enough to include the phrase that introduces the
/// figure ("The typical base pay range for this role across the U.S. is …") and stops shortly after,
/// snapping to word boundaries so it doesn't start or end mid-word.
private func payWindow(in text: String, around money: Range<String.Index>) -> String {
    let before = 220
    let after = 90
    let lower = text.index(money.lowerBound, offsetBy: -before, limitedBy: text.startIndex) ?? text.startIndex
    let upper = text.index(money.upperBound, offsetBy: after, limitedBy: text.endIndex) ?? text.endIndex
    var slice = String(text[lower ..< upper])
    // Drop a partial leading word unless we started at the very beginning.
    if lower != text.startIndex, let space = slice.firstIndex(of: " ") {
        slice = String(slice[slice.index(after: space)...])
    }
    if upper != text.endIndex, let space = slice.lastIndex(of: " ") {
        slice = String(slice[..<space])
    }
    return slice.trimmingCharacters(in: .whitespaces)
}

/// Abbreviations whose trailing period does not end a sentence. Without these, Microsoft's "…across
/// the U.S. is USD $142,800 - $274,800 per year." splits after "U.S." and the recovered fragment
/// loses the "base pay range" context that makes it readable.
private let sentenceSafeAbbreviations: Set<String> = [
    "u.s.", "u.s.a.", "u.k.", "e.g.", "i.e.", "etc.", "vs.", "approx.", "inc.", "ltd.", "co.",
    "corp.", "dept.", "est.", "no.", "yr.", "yrs.", "hr.", "hrs.", "mr.", "ms.", "mrs.", "dr.", "st."
]

/// Split on sentence terminators followed by whitespace, keeping known abbreviations intact.
private func splitIntoSentences(_ text: String) -> [String] {
    let characters = Array(text)
    var sentences: [String] = []
    var current = ""
    for (index, char) in characters.enumerated() {
        current.append(char)
        guard char == ".", index + 1 < characters.count,
              characters[index + 1] == " " || characters[index + 1] == "\n" else { continue }
        // The token ending at this period — "U.S." rather than the whole clause.
        let token = current.split(whereSeparator: { $0 == " " || $0 == "\n" }).last.map(String.init) ?? ""
        if sentenceSafeAbbreviations.contains(token.lowercased()) { continue }
        sentences.append(current)
        current = ""
    }
    if !current.isEmpty { sentences.append(current) }
    return sentences
}

// MARK: - JSON-LD helpers

private func extractJsonLdDescription(_ structuredData: [[String: Any]]) -> String {
    for item in structuredData {
        guard let posting = findJobPosting(item) else { continue }
        var parts: [String] = []
        if let locType = posting["jobLocationType"] as? String, locType == "TELECOMMUTE" {
            parts.append("Work arrangement: Remote")
        }
        // JSON-LD carries the pay band as STRUCTURED data (baseSalary.value.minValue/maxValue). It was
        // being dropped entirely: only `description` and `jobLocationType` were surfaced, so a posting
        // whose salary lives solely in markup — or whose visible salary line the boilerplate stripper
        // removes — reached the model with no pay information at all and extracted as null (job #581,
        // LiveKit: "$225K – $265K" present in the capture, absent from the cleaned text).
        if let salary = jsonLdSalaryLine(posting) { parts.append(salary) }
        if let desc = posting["description"] as? String, !desc.trimmingCharacters(in: .whitespaces).isEmpty {
            parts.append(stripHtml(desc))
        }
        if !parts.isEmpty { return parts.joined(separator: "\n") }
    }
    return ""
}

/// A plain-text pay line from JSON-LD `baseSalary`, or nil when absent/unusable.
///
/// schema.org allows the amount as a `QuantitativeValue` (min/max or a single `value`) and the numbers
/// as either JSON numbers or strings, so both are accepted. Emitted as text rather than written
/// straight to the job's salary fields so it flows through the existing normalization and stays
/// visible to a reader of the description.
private func jsonLdSalaryLine(_ posting: [String: Any]) -> String? {
    guard let base = posting["baseSalary"] as? [String: Any] else { return nil }
    let currency = (base["currency"] as? String) ?? (base["salaryCurrency"] as? String) ?? ""
    guard let value = base["value"] as? [String: Any] else { return nil }

    func number(_ key: String) -> Double? {
        if let n = value[key] as? Double { return n }
        if let n = value[key] as? Int { return Double(n) }
        if let s = value[key] as? String { return Double(s.filter { $0.isNumber || $0 == "." }) }
        return nil
    }
    func format(_ n: Double) -> String {
        n == n.rounded() ? String(Int(n)) : String(n)
    }

    let unit = (value["unitText"] as? String)?.lowercased()
    let period = unit.map { " per \($0)" } ?? ""
    let amount: String
    if let min = number("minValue"), let max = number("maxValue"), min > 0, max > 0 {
        amount = min == max ? format(min) : "\(format(min))–\(format(max))"
    } else if let single = number("value"), single > 0 {
        amount = format(single)
    } else {
        return nil
    }
    return "Base salary: \(amount)\(currency.isEmpty ? "" : " \(currency)")\(period)"
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

// MARK: - Location recovery from structured data

/// Location statements taken from schema.org `JobPosting` fields.
///
/// The location the posting's own page states, if any (TASK-675).
///
/// Deliberately returns the matched PHRASE rather than a yes/no, because the caller needs something
/// to put in the text: a JSON-LD body promoted over the page text takes the location with it, and the
/// model then has nothing to go on. Ordered most-specific first — "USA - Remote" says more than a
/// bare "Remote", and a city/region pair says more than either.
func pageLocationPhrase(_ text: String) -> String? {
    guard !text.isEmpty else { return nil }
    // Each pattern carries its own options, because the city form DEPENDS on capitalisation: with
    // `.caseInsensitive` its `[A-Z]` matches lowercase too, and "Based in Los Gatos, California"
    // matched from "in" rather than from the city.
    let patterns: [(pattern: String, options: NSString.CompareOptions)] = [
        // "USA - Remote", "US — Remote", "Remote - United States", "Remote — Europe".
        // The left side is ONE token (no spaces) so "Title USA - Remote" can't match from "Title".
        (
            #"\b(?:remote\s*[-–—]\s*[A-Za-z][A-Za-z .]{1,30}|[A-Za-z.]{2,20}\s*[-–—]\s*remote)\b"#,
            [.regularExpression, .caseInsensitive]
        ),
        // "Los Gatos, California", "Austin, TX", "London, United Kingdom" — capitalisation is the
        // signal, so this one is case-SENSITIVE.
        (
            #"\b[A-Z][a-zA-Z.'-]+(?:[ ][A-Z][a-zA-Z.'-]+){0,2},\s*(?:[A-Z]{2}\b|[A-Z][a-z]+)"#,
            [.regularExpression]
        ),
        // Last resort: the bare word, which at least distinguishes remote from on-site.
        (#"\b(?:fully\s+remote|work\s+from\s+home|remote)\b"#, [.regularExpression, .caseInsensitive])
    ]
    for (pattern, options) in patterns {
        guard let range = text.range(of: pattern, options: options) else { continue }
        let phrase = text[range].trimmingCharacters(in: .whitespacesAndNewlines)
        if !phrase.isEmpty { return phrase }
    }
    return nil
}

/// Whether the posting's own text already says where the job is.
///
/// The discriminator for whether structured-data location should speak at all (TASK-675). Cheap and
/// deliberately generous: any remote wording, or a "City, ST"/"City, Country" pair, counts. Being
/// generous is the safe direction — it only means trusting the posting's prose over its metadata,
/// and the prose is what a human reads.
func textNamesALocation(_ text: String) -> Bool {
    if text.isEmpty { return false }
    if RemoteTypeInferer.sourceIndicatesRemote(text) { return true }
    if LocationInferer.remoteLocationFromSource(text) != nil { return true }
    // The bare word, anywhere. The existing helpers are stricter than this needs to be: one wants
    // specific remote-work phrasing, the other wants the LINE to start with "Remote" — and the
    // posting that motivated this says "USA - Remote", which is neither. A page that uses the word
    // at all has an opinion about where the job is, and that opinion beats its own metadata.
    if text.range(of: #"\bremote\b"#, options: [.regularExpression, .caseInsensitive]) != nil {
        return true
    }
    // "Los Gatos, California", "Austin, TX", "London, United Kingdom".
    let cityRegion = #"\b[A-Z][a-zA-Z.'-]+(?:[ ][A-Z][a-zA-Z.'-]+){0,2},\s*(?:[A-Z]{2}\b|[A-Z][a-z]+)"#
    return text.range(of: cityRegion, options: .regularExpression) != nil
}

/// `extractJsonLdDescription` already surfaces `jobLocationType` (TELECOMMUTE) and the pay band, but
/// never `jobLocation` — so a posting whose prose description doesn't name a city reached the model
/// with no location at all and extracted as `unknown`, which the criteria check reads as on-site.
/// Reddit #7944159 published `addressLocality: "Remote - United States"` in JSON-LD, said nothing
/// about location in the description, and duly scored as a non-remote job.
func structuredLocationLines(
    _ structuredData: [[String: Any]]
) -> [(label: String, value: String, isPlacementClaim: Bool)] {
    var lines: [(label: String, value: String, isPlacementClaim: Bool)] = []
    var seen = Set<String>()

    /// - Parameter isPlacementClaim: true for `jobLocation` ("the job is HERE"), which the posting's
    ///   own text can outrank; false for an eligibility restriction, which nothing else states.
    func add(_ label: String, _ value: String, isPlacementClaim: Bool) {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, seen.insert(trimmed.lowercased()).inserted else { return }
        lines.append((label, trimmed, isPlacementClaim))
    }

    /// `jobLocation` is one object or an array of them (multi-site postings).
    func places(_ value: Any?) -> [[String: Any]] {
        if let one = value as? [String: Any] { return [one] }
        if let many = value as? [[String: Any]] { return many }
        return []
    }

    for item in structuredData {
        guard let posting = findJobPosting(item) else { continue }

        for place in places(posting["jobLocation"]) {
            guard let address = place["address"] as? [String: Any] else { continue }
            // Locality, region, country — enough to judge geography without pasting a street address
            // into the prompt.
            let fields = ["addressLocality", "addressRegion", "addressCountry"]
                .compactMap { address[$0] as? String }
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
            if !fields.isEmpty {
                add("Location", fields.joined(separator: ", "), isPlacementClaim: true)
            }
        }

        // Where a remote role may actually be performed — the difference between "Remote" and
        // "Remote, but only from Portugal", which decides whether it meets the user's criteria.
        for req in places(posting["applicantLocationRequirements"]) {
            if let name = req["name"] as? String {
                add("Remote eligible in", name, isPlacementClaim: false)
            }
        }
    }
    return lines
}
