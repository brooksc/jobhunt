// swiftlint:disable line_length
import Foundation

// MARK: - SalaryNormalizer

/// Mirrors normalizeSalaryFromSource() and helpers from server/extract.js.
/// Pure functions — no I/O, no SwiftData.
public enum SalaryNormalizer {
    // MARK: - Public entry point

    /// Normalizes salary fields from a raw extracted dict + optional source context.
    /// Returns a new dict with corrected salary_min, salary_max, salary_currency,
    /// salary_hourly_min, salary_hourly_max.
    public static func normalize(
        extracted: [String: Any?],
        preferredLocations: String? = nil,
        sourceText: String? = nil
    ) -> [String: Any?] {
        let note = (extracted["salary_note"] as? String) ?? ""
        if note.trimmingCharacters(in: .whitespaces).isEmpty {
            // No salary_note — try to recover from raw source text (e.g. Workday format)
            guard let src = sourceText, !src.isEmpty else { return extracted }
            let currency = normalizeSalaryCurrency(extracted["salary_currency"] as? String, note: src)
            let filteredSrc = salaryTextForCurrency(src, currency: currency)
            var out = extracted
            out["salary_currency"] = currency as Any?
            if let band = resolveSalaryBand(
                salaryBands(filteredSrc),
                preferredLocations: preferredLocations,
                note: filteredSrc
            ) {
                out["salary_min"] = boundedSalaryInt(band.min) as Any?
                out["salary_max"] = boundedSalaryInt(band.max) as Any?
                return out
            }
            let amounts = moneyAmounts(filteredSrc).filter { $0 >= 1000 }
            if let minMaxPair = minMax(amounts) {
                out["salary_min"] = boundedSalaryInt(minMaxPair.min) as Any?
                out["salary_max"] = boundedSalaryInt(minMaxPair.max) as Any?
            }
            return out
        }

        let currency = normalizeSalaryCurrency(extracted["salary_currency"] as? String, note: note)
        let salaryText = salaryTextForCurrency(note, currency: currency)

        // Hourly path
        let hourlyAmts = hourlyAmounts(salaryText)
        if let minMaxPair = minMax(hourlyAmts) {
            var out = extracted
            out["salary_currency"] = currency as Any?
            out["salary_hourly_min"] = minMaxPair.min as Any?
            out["salary_hourly_max"] = minMaxPair.max as Any?
            out["salary_min"] = boundedSalaryInt(minMaxPair.min * 2080) as Any?
            out["salary_max"] = boundedSalaryInt(minMaxPair.max * 2080) as Any?
            return out
        }

        // Source text band selection (when preferred locations are set)
        if let src = sourceText, !src.isEmpty {
            let specificTerms = specificPreferredTerms(preferredLocations)
            if !specificTerms.isEmpty {
                let sourceSalaryText = salaryTextForCurrency(src, currency: currency)
                if let band = resolveSalaryBand(
                    salaryBands(sourceSalaryText),
                    preferredLocations: preferredLocations,
                    note: sourceSalaryText
                ) {
                    var out = extracted
                    out["salary_currency"] = currency as Any?
                    out["salary_min"] = boundedSalaryInt(band.min) as Any?
                    out["salary_max"] = boundedSalaryInt(band.max) as Any?
                    return out
                }
            }
        }

        // Salary note band selection. This text is the model's `salary_note` — a field that is by
        // definition about pay — so a range in it needs no further evidence that it is money. The two
        // whole-page scans above keep the evidence requirement: that's prose, and prose is where the
        // invented year ranges came from.
        if let band = resolveSalaryBand(
            salaryBands(salaryText, requirePayEvidence: false),
            preferredLocations: preferredLocations,
            note: salaryText
        ) {
            var out = extracted
            out["salary_currency"] = currency as Any?
            out["salary_min"] = boundedSalaryInt(band.min) as Any?
            out["salary_max"] = boundedSalaryInt(band.max) as Any?
            return out
        }

        // Fall back to min/max of all annual amounts
        let annualAmounts = moneyAmounts(salaryText).filter { $0 >= 1000 }
        var out = extracted
        out["salary_currency"] = currency as Any?
        if let minMaxPair = minMax(annualAmounts) {
            out["salary_min"] = boundedSalaryInt(minMaxPair.min) as Any?
            out["salary_max"] = boundedSalaryInt(minMaxPair.max) as Any?
        }
        return out
    }

    // MARK: - Salary amount parsing

    public struct SalaryRange {
        public let min: Double
        public let max: Double
        public let label: String
    }

    static func parseSalaryAmount(_ raw: String) -> Double? {
        let text = raw.trimmingCharacters(in: .whitespaces).lowercased()
        let pattern = #"(\d+(?:,\d{3})*(?:\.\d+)?|\d+(?:\.\d+)?)\s*([kK])?"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) else { return nil }
        let numStr = (text as NSString).substring(with: match.range(at: 1)).replacingOccurrences(of: ",", with: "")
        guard let value = Double(numStr), value.isFinite else { return nil }
        let suffixRange = match.range(at: 2)
        if suffixRange.location != NSNotFound, let suffixRangeResult = Range(suffixRange, in: text),
           !text[suffixRangeResult].isEmpty {
            return value * 1000
        }
        return value
    }

    /// Retirement-plan account names — "401k", "401(k)", "403(b)", "457(b)", "457b" — embed a number
    /// that the bare k-notation money pattern below would otherwise read as a salary: a
    /// "401k with employer match" benefit line becomes a bogus $401,000 (job #163). These tokens are
    /// benefits, never pay, so strip them before parsing money. A currency-prefixed "$401K" is left
    /// intact (negative lookbehind) so a genuine — if rare — "$401K" salary still parses.
    static func stripRetirementPlanTokens(_ text: String) -> String {
        let pattern = #"(?<![$€£\d,.])\b(?:401|403|457)\s*\(?\s*[kb]\)?"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { return text }
        return regex.stringByReplacingMatches(
            in: text,
            range: NSRange(text.startIndex..., in: text),
            withTemplate: " "
        )
    }

    /// Extract all money amounts from text (handles ranges, currency symbols, k notation).
    static func moneyAmounts(_ text: String) -> [Double] {
        let text = stripRetirementPlanTokens(text)
        var amounts: [Double] = []

        // Range patterns (return pairs)
        let rangePatterns: [(String, Int)] = [
            // currency-prefix range: "USD $133,400 - $226,600" or "USD 133,400 - 226,600"
            (
                #"(?:USD|CAD|EUR|GBP)\s*\$?\s*(\d+(?:,\d{3})*(?:\.\d+)?|\d+(?:\.\d+)?)\s*([kK])?\s*[-–—]\#(upperBoundLeadIn)(\d+(?:,\d{3})*(?:\.\d+)?|\d+(?:\.\d+)?)\s*([kK])?"#,
                4
            ),
            // symbol prefix range: "$133,400 - $226,600"
            (
                #"[$€£]\s*(\d+(?:,\d{3})*(?:\.\d+)?|\d+(?:\.\d+)?)\s*([kK])?\s*[-–—]\#(upperBoundLeadIn)(\d+(?:,\d{3})*(?:\.\d+)?|\d+(?:\.\d+)?)\s*([kK])?"#,
                4
            ),
            // currency-suffix range: "133,400 - 226,600 USD"
            (
                #"\b(\d+(?:,\d{3})*(?:\.\d+)?|\d+(?:\.\d+)?)\s*([kK])?\s*[-–—]\s*(\d+(?:,\d{3})*(?:\.\d+)?|\d+(?:\.\d+)?)\s*([kK])?\s*(?:USD|CAD|EUR|GBP)\b"#,
                4
            )
        ]
        for (pattern, _) in rangePatterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { continue }
            let nsText = text as NSString
            let matches = regex.matches(in: text, range: NSRange(text.startIndex..., in: text))
            for mtch in matches {
                let group1 = nsText.substring(with: mtch.range(at: 1))
                let group2 = mtch.range(at: 2).location != NSNotFound ? nsText.substring(with: mtch.range(at: 2)) : ""
                let group3 = nsText.substring(with: mtch.range(at: 3))
                let group4 = mtch.range(at: 4).location != NSNotFound ? nsText.substring(with: mtch.range(at: 4)) : ""
                let suffix = group4.isEmpty ? group2 : group4
                if let val1 = parseSalaryAmount(group1 + (group2.isEmpty ? suffix : group2)) { amounts.append(val1) }
                if let val2 = parseSalaryAmount(group3 + suffix) { amounts.append(val2) }
            }
        }

        // Single-value patterns
        let singlePatterns = [
            #"[$€£]\s*(\d+(?:,\d{3})*(?:\.\d+)?|\d+(?:\.\d+)?)\s*([kK])?"#,
            #"(?:USD|CAD|EUR|GBP)\s*\$?\s*(\d+(?:,\d{3})*(?:\.\d+)?|\d+(?:\.\d+)?)\s*([kK])?"#,
            #"\b(\d+(?:,\d{3})*(?:\.\d+)?|\d+(?:\.\d+)?)\s*([kK])?\s*(?:USD|CAD|EUR|GBP)\b"#,
            #"\b(\d+(?:\.\d+)?)\s*([kK])\b"#
        ]
        for pattern in singlePatterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { continue }
            let nsText = text as NSString
            let matches = regex.matches(in: text, range: NSRange(text.startIndex..., in: text))
            for mtch in matches {
                let group1 = nsText.substring(with: mtch.range(at: 1))
                let group2 = mtch.range(at: 2).location != NSNotFound ? nsText.substring(with: mtch.range(at: 2)) : ""
                if let parsedAmt = parseSalaryAmount(group1 + group2) { amounts.append(parsedAmt) }
            }
        }

        // Deduplicate while preserving order (Set loses order)
        var seen = Set<Double>()
        return amounts.filter { seen.insert($0).inserted }
    }

    /// Extract hourly pay amounts (only if text mentions hr/hour/hourly).
    static func hourlyAmounts(_ text: String) -> [Double] {
        let hrPattern = #"\b(?:hr|hour|hourly)\b|/\s*(?:hr|hour)"#
        guard (try? NSRegularExpression(pattern: hrPattern, options: .caseInsensitive))?.firstMatch(
            in: text, range: NSRange(text.startIndex..., in: text)
        ) != nil else { return [] }

        var amounts = moneyAmounts(text).filter { $0 > 0 && $0 < 1000 }

        // Also match "50 - 150 USD/hr" style ranges
        let rangeHourly = #"(\d+(?:\.\d+)?)\s*[-–—]\s*(\d+(?:\.\d+)?)\s*(?:USD|CAD|EUR|GBP)?\s*/?\s*(?:hr|hour)\b"#
        if let regex = try? NSRegularExpression(pattern: rangeHourly, options: .caseInsensitive) {
            let nsText = text as NSString
            for match in regex.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
                if let val1 = Double(nsText.substring(with: match.range(at: 1))) { amounts.append(val1) }
                if let val2 = Double(nsText.substring(with: match.range(at: 2))) { amounts.append(val2) }
            }
        }

        var seen = Set<Double>()
        return amounts.filter { seen.insert($0).inserted }
    }

    static func minMax(_ values: [Double]) -> (min: Double, max: Double)? {
        let nums = values.filter(\.isFinite)
        guard !nums.isEmpty, let minVal = nums.min(), let maxVal = nums.max() else { return nil }
        return (min: minVal, max: maxVal)
    }

    /// Non-trapping Double→Int for a salary amount. Untrusted capture text and model output can carry
    /// values above `Int.max` (or non-finite), and the trapping `Int(Double)` would abort the whole
    /// process (CWE-190). Clamps to `[0, 1_000_000_000]` so an absurd amount becomes a visibly-bogus
    /// bound instead of crashing extraction (which the queue would otherwise re-run into a crash loop).
    static func boundedSalaryInt(_ value: Double) -> Int {
        guard value.isFinite else { return 0 }
        let rounded = value.rounded()
        if rounded <= 0 { return 0 }
        let ceiling = 1_000_000_000.0 // $1B/yr — far above any real salary
        return rounded >= ceiling ? Int(ceiling) : Int(rounded)
    }

    // MARK: - Currency detection

    static func currencyFromSalaryNote(_ note: String) -> String? {
        // USD/CAD or CAD/USD → USD
        if note
            .range(of: #"\bUSD\s*/\s*CAD\b|\bCAD\s*/\s*USD\b"#, options: [.regularExpression, .caseInsensitive]) !=
            nil { return "USD" }
        if note.range(of: #"\bUSD\b|\$"#, options: [.regularExpression, .caseInsensitive]) != nil { return "USD" }
        if note.range(of: #"\bEUR\b|€"#, options: [.regularExpression, .caseInsensitive]) != nil { return "EUR" }
        if note.range(of: #"\bGBP\b|£"#, options: [.regularExpression, .caseInsensitive]) != nil { return "GBP" }
        if note.range(of: #"\bCAD\b"#, options: [.regularExpression, .caseInsensitive]) != nil { return "CAD" }
        return nil
    }

    static func normalizeSalaryCurrency(_ currency: String?, note: String) -> String? {
        let value = (currency ?? "").trimmingCharacters(in: .whitespaces).uppercased()
        if ["USD", "CAD", "EUR", "GBP"].contains(value) { return value }
        return currencyFromSalaryNote(note)
    }

    /// Filter salary text to only lines/parts relevant to the target currency.
    static func salaryTextForCurrency(_ text: String, currency: String?) -> String {
        guard let currency else { return text }
        let otherCurrencies: [String: String] = [
            "USD": #"\b(?:CAD|EUR|GBP)\b|[€£]"#,
            "CAD": #"\b(?:USD|EUR|GBP)\b|[$€£]"#,
            "EUR": #"\b(?:USD|CAD|GBP)\b|[$£]"#,
            "GBP": #"\b(?:USD|CAD|EUR)\b|[$€]"#
        ]
        let ownCurrencies: [String: String] = [
            "USD": #"\bUSD\b|\$"#,
            "CAD": #"\bCAD\b"#,
            "EUR": #"\bEUR\b|€"#,
            "GBP": #"\bGBP\b|£"#
        ]
        guard let ownPattern = ownCurrencies[currency],
              let otherPattern = otherCurrencies[currency] else { return text }
        // Only filter if other currencies actually appear
        guard text.range(of: otherPattern, options: [.regularExpression, .caseInsensitive]) != nil else { return text }
        let parts = text.components(separatedBy: CharacterSet(charactersIn: ";\n"))
            .map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        let filtered = parts.filter {
            $0.range(of: ownPattern, options: [.regularExpression, .caseInsensitive]) != nil &&
                $0.range(of: otherPattern, options: [.regularExpression, .caseInsensitive]) == nil
        }
        return filtered.isEmpty ? text : filtered.joined(separator: "\n")
    }

    // MARK: - Salary band parsing

    static func salaryRangeValue(
        _ first: String,
        _ firstSuffix: String,
        _ second: String,
        _ secondSuffix: String
    ) -> (min: Double, max: Double)? {
        let suffix = secondSuffix.isEmpty ? firstSuffix : secondSuffix
        guard let low = parseSalaryAmount(first + (firstSuffix.isEmpty ? suffix : firstSuffix)),
              let high = parseSalaryAmount(second + suffix),
              low >= 1000, high >= 1000 else { return nil }
        return (min: Swift.min(low, high), max: Swift.max(low, high))
    }

    /// What may sit between a range's dash and its upper amount.
    ///
    /// Every range pattern below used to allow only an optional `$` there, which silently failed on
    /// the common style of repeating the currency code on BOTH sides — GitHub's board writes
    /// `USD $140,400.00 - USD $372,300.00 /Yr.`. No range matched, so the values only came through as
    /// loose single amounts, and the whole-page fallback then took the smallest money on the page:
    /// a $5,000 signing bonus became the salary floor.
    static let upperBoundLeadIn = #"\s*(?:USD|CAD|EUR|GBP)?\s*[$€£]?\s*"#

    static func lineRange(_ line: String) -> (min: Double, max: Double)? {
        let patterns = [
            // currency-prefix range
            #"(?:USD|CAD|EUR|GBP)\s*\$?\s*(\d+(?:,\d{3})*(?:\.\d+)?|\d+(?:\.\d+)?)\s*([kK])?\s*[-–—]\#(upperBoundLeadIn)(\d+(?:,\d{3})*(?:\.\d+)?|\d+(?:\.\d+)?)\s*([kK])?"#,
            // symbol-prefix range
            #"[$€£]\s*(\d+(?:,\d{3})*(?:\.\d+)?|\d+(?:\.\d+)?)\s*([kK])?\s*[-–—]\#(upperBoundLeadIn)(\d+(?:,\d{3})*(?:\.\d+)?|\d+(?:\.\d+)?)\s*([kK])?"#,
            // currency-suffix range
            #"\b(\d+(?:,\d{3})*(?:\.\d+)?|\d+(?:\.\d+)?)\s*([kK])?\s*[-–—]\s*(\d+(?:,\d{3})*(?:\.\d+)?|\d+(?:\.\d+)?)\s*([kK])?\s*(?:USD|CAD|EUR|GBP)\b"#
        ]
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
                  let match = regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)) else { continue }
            let nsText = line as NSString
            let group1 = nsText.substring(with: match.range(at: 1))
            let group2 = match.range(at: 2).location != NSNotFound ? nsText.substring(with: match.range(at: 2)) : ""
            let group3 = nsText.substring(with: match.range(at: 3))
            let group4 = match.range(at: 4).location != NSNotFound ? nsText.substring(with: match.range(at: 4)) : ""
            if let bandResult = salaryRangeValue(group1, group2, group3, group4) { return bandResult }
        }
        return nil
    }

    /// Wording that makes a bare numeric range pay rather than years, headcount or percentages.
    static let payContextPattern =
        #"\bper\s+year\b|\bper\s+annum\b|\bper\s+hour\b|\bannually\b|\bannuali[sz]ed\b|\bannual\b|\bhourly\b|/\s*(?:hr|yr|hour|year)\b|\bsalary\b|\bsalaries\b|\bbase\s+pay\b|\bcompensation\b|\bpay\s+(?:range|band|scale)\b|\bhiring\s+range\b|\bpay\s+transparency\b"#

    /// Does a matched range carry evidence that it is about MONEY?
    ///
    /// The inline range pattern in `salaryBands` had every currency marker optional, so it degenerated
    /// to `\d+\s*-\s*\d+`: any two dash-separated numbers became a candidate band, filtered only by
    /// the ">= 1000 on both ends" test in `salaryRangeValue`. A magnitude floor cannot tell a year
    /// from a wage — job #1502 (SageSure) states no pay yet stored $2,020–$2,023 from "… four years in
    /// a row (2020-2023)" — and raising it would reject real hourly bands. So require affirmative
    /// evidence: a currency symbol or code, or a k/K suffix, in the match; failing that, pay wording
    /// in its sentence.
    static func rangeLooksLikePay(match: String, sentence: String) -> Bool {
        let currency = #"[$€£]|\b(?:USD|CAD|EUR|GBP)\b"#
        let opts: String.CompareOptions = [.regularExpression, .caseInsensitive]
        if match.range(of: currency, options: opts) != nil { return true }
        if match.range(of: #"\d\s*[kK]\b"#, options: .regularExpression) != nil { return true }
        return sentence.range(of: payContextPattern, options: opts) != nil
    }

    /// Is the character at `idx` a sentence end — a newline, or a period that isn't a decimal point?
    ///
    /// A period BETWEEN digits is a decimal point. Treating it as a terminator cut the sentence off
    /// mid-number — "120,000.00 - 193,725.00 annually" ended at "120,000", losing the `annually` that
    /// proves it is pay — and four real bands were rejected (#415, #600, #944, #1027).
    static func isSentenceEnd(_ nsText: NSString, _ idx: Int) -> Bool {
        func isDigit(_ offset: Int) -> Bool {
            guard offset >= 0, offset < nsText.length else { return false }
            return (48 ... 57).contains(nsText.character(at: offset))
        }
        let char = nsText.character(at: idx)
        if char == 10 { return true } // \n
        guard char == 46 else { return false } // .
        return !(isDigit(idx - 1) && isDigit(idx + 1))
    }

    static func sentenceForIndex(_ text: String, _ index: Int) -> String {
        let nsText = text as NSString
        let from = Swift.max(0, Swift.min(index, nsText.length))
        let start = (0 ..< from).reversed().first { isSentenceEnd(nsText, $0) }.map { $0 + 1 } ?? 0
        let end = (from ..< nsText.length).first { isSentenceEnd(nsText, $0) } ?? nsText.length
        return nsText.substring(with: NSRange(start ..< end)).trimmingCharacters(in: .whitespaces)
    }

    /// Parse multi-band salary ranges from text (line-by-line + inline regex).
    ///
    /// `requirePayEvidence` answers "is this text ABOUT pay?". Scanning a whole posting, nothing says
    /// a dash-separated pair is money, so a match must earn it (`rangeLooksLikePay`). When the text IS
    /// the model's `salary_note`, the field settles it — "103,500 - 181,000" has no currency, no k and
    /// no pay wording, and is pay all the same (job #451).
    public static func salaryBands(_ text: String, requirePayEvidence: Bool = true) -> [SalaryRange] {
        var bands: [SalaryRange] = []
        let lines = text.components(separatedBy: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        for (idx, line) in lines.enumerated() {
            guard let range = lineRange(line) else { continue }
            let previous = (idx > 0 && lineRange(lines[idx - 1]) == nil) ? lines[idx - 1] : ""
            let label = (previous + " " + line).trimmingCharacters(in: .whitespaces)
            bands.append(SalaryRange(min: range.min, max: range.max, label: label))
        }

        // Also catch inline ranges not caught by line-by-line
        let rangeRe = #"(?:USD|CAD|EUR|GBP)?\s*\$?\s*(\d+(?:,\d{3})*(?:\.\d+)?|\d+(?:\.\d+)?)\s*([kK])?\s*[-–—]\#(upperBoundLeadIn)(\d+(?:,\d{3})*(?:\.\d+)?|\d+(?:\.\d+)?)\s*([kK])?\s*(?:per year|annually|annual|USD|CAD|EUR|GBP)?"#
        if let regex = try? NSRegularExpression(pattern: rangeRe, options: .caseInsensitive) {
            let nsText = text as NSString
            for match in regex.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
                let group1 = nsText.substring(with: match.range(at: 1))
                let group2 = match.range(at: 2).location != NSNotFound ? nsText.substring(with: match.range(at: 2)) : ""
                let group3 = nsText.substring(with: match.range(at: 3))
                let group4 = match.range(at: 4).location != NSNotFound ? nsText.substring(with: match.range(at: 4)) : ""
                guard let range = salaryRangeValue(group1, group2, group3, group4) else { continue }
                if bands.contains(where: { $0.min == range.min && $0.max == range.max }) { continue }
                let label = sentenceForIndex(text, match.range.location)
                // Every currency marker in this pattern is optional, so the match alone proves nothing
                // about pay — see `rangeLooksLikePay`.
                if requirePayEvidence,
                   !rangeLooksLikePay(match: nsText.substring(with: match.range), sentence: label) { continue }
                bands.append(SalaryRange(min: range.min, max: range.max, label: label))
            }
        }
        return bands
    }

    // MARK: - Band selection

    static func specificPreferredTerms(_ preferredLocations: String?) -> [String] {
        parsePreferredLocations(preferredLocations).filter { term in
            let lower = term.lowercased().trimmingCharacters(in: .whitespaces)
            return !["remote", "united states", "usa", "us", "u.s.", "u.s.a."].contains(lower)
        }
    }

    /// The band to use, given everything parsed out of a piece of text.
    ///
    /// `selectSalaryBand` answers a narrower question — which of SEVERAL location-specific bands
    /// applies — and returns nil when there is only one. The callers then fell through to "min and max
    /// of every money amount in the text", which on a real posting is a worse answer rather than a
    /// safer one: GitHub's page carries a $5,000 signing bonus beside the range, so the loose scan made
    /// $5,000 the salary floor.
    ///
    /// A single parsed band is better evidence than the smallest number on the page — it already
    /// required a currency marker and both ends over $1,000 (`salaryRangeValue`).
    static func resolveSalaryBand(
        _ bands: [SalaryRange], preferredLocations: String?, note: String
    ) -> SalaryRange? {
        if let chosen = selectSalaryBand(bands, preferredLocations: preferredLocations, note: note) {
            return chosen
        }
        return bands.count == 1 ? bands[0] : nil
    }

    static func selectSalaryBand(_ bands: [SalaryRange], preferredLocations: String?, note: String) -> SalaryRange? {
        guard bands.count > 1 else { return nil }
        let terms = specificPreferredTerms(preferredLocations)

        // Try to find a band matching user's preferred location terms
        for band in bands where terms.contains(where: { termMatches(band.label, term: $0) }) {
            return band
        }

        let allOtherUSPattern = #"\bacross the U\.?S\.?\b|\ball (?:other )?U\.?S\.? locations\b|\bUnited States\b"#
        // When user has specific location preferences but none matched, use "All Other US" band
        if !terms.isEmpty {
            if let allOtherUS = bands.first(where: { $0.label.range(
                of: allOtherUSPattern,
                options: [.regularExpression, .caseInsensitive]
            ) != nil }) {
                return allOtherUS
            }
        }

        // "different range" note → use "All Other US" band
        if note.range(of: "different range applicable to specific work locations", options: .caseInsensitive) != nil {
            return bands.first(where: { $0.label.range(
                of: allOtherUSPattern,
                options: [.regularExpression, .caseInsensitive]
            ) != nil }) ?? nil
        }

        return nil
    }
}

// MARK: - RemoteTypeInferer

/// Mirrors normalizeRemoteTypeFromSource() from server/extract.js.
/// Pure functions — no I/O, no SwiftData.
public enum RemoteTypeInferer {
    // MARK: - Public entry point

    /// Returns updated extracted dict with corrected remote_type.
    public static func normalize(extracted: [String: Any?], description: String?, url: String?) -> [String: Any?] {
        if (extracted["remote_type"] as? String) == "remote" { return extracted }
        if sourceIndicatesRemote(description) || urlIndicatesRemote(url) {
            var out = extracted
            out["remote_type"] = "remote" as Any?
            return out
        }
        let text = description ?? ""
        let hybridPattern = #"\bWork site\s*[1-5]\s+days?\s*/\s*week\s+in-office\b"#
        if text.range(of: hybridPattern, options: [.regularExpression, .caseInsensitive]) != nil {
            var out = extracted
            out["remote_type"] = "hybrid" as Any?
            return out
        }
        return extracted
    }

    // MARK: - Heuristics

    static func sourceIndicatesRemote(_ description: String?) -> Bool {
        let text = description ?? ""
        if text.isEmpty { return false }
        // Patterns that need anchorsMatchLines (start of line checks)
        let anchoredPatterns = [
            #"^Remote(?:\s*[-–—]\s*(?:United States|USA|U\.S\.|US))?\b"#,
            #"^Work arrangement:\s*Remote\b"#
        ]
        for pattern in anchoredPatterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .anchorsMatchLines]),
               regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil {
                return true
            }
        }
        // Patterns that are anywhere in text
        let inlinePatterns = [
            #"\bWork site\s*0\s+days?\s*/\s*week\s+in-office\b"#,
            #"\bRemote\s+or\s+Hybrid\b"#,
            #"\bopen to remote candidates\b"#,
            #"\bHiring Remotely\b"#,
            #"\bFully Remote\b"#,
            #"\bWork from Home\b"#,
            #"\bTelecommute\b"#,
            #""jobLocationType"\s*:\s*"TELECOMMUTE""#
        ]
        for pattern in inlinePatterns
            where text.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil {
            return true
        }
        return false
    }

    /// Check job-board URL params for explicit remote filter signals.
    static func urlIndicatesRemote(_ url: String?) -> Bool {
        guard let urlStr = url, !urlStr.isEmpty,
              let parsedURL = URL(string: urlStr),
              let components = URLComponents(url: parsedURL, resolvingAgainstBaseURL: false) else { return false }
        let host = parsedURL.host ?? ""
        // A query parameter may legitimately repeat, and this crashed the app when one did.
        // `Dictionary(uniqueKeysWithValues:)` traps on a duplicate key, and Netflix's board writes
        // `?…&Teams=Engineering&Teams=Engineering%20Operations`, so capturing one of its postings
        // killed the process mid-extraction and left the job stuck in `running`, never parsed.
        //
        // Collecting every value is also more correct than keeping one: a job board expresses "remote
        // OR onsite" as a repeated filter (`f_WT=1&f_WT=2`), and a last-one-wins dictionary would
        // report whichever happened to come last.
        var params: [String: [String]] = [:]
        for item in components.queryItems ?? [] {
            guard let value = item.value else { continue }
            params[item.name, default: []].append(value)
        }
        func has(_ name: String, _ value: String) -> Bool {
            params[name]?.contains(value) ?? false
        }

        if host.contains("levels.fyi") {
            let perkIds = (params["perkIds"] ?? []).flatMap { $0.split(separator: ",").map(String.init) }
            if perkIds.contains("58") { return true }
        }
        if host.contains("indeed.com") {
            if has("remotejob", "1") || has("l", "Remote") { return true }
        }
        if host.contains("linkedin.com") {
            if has("f_WT", "2") { return true }
        }
        if host.contains("glassdoor.com") {
            if has("remoteWorkType", "1") { return true }
        }
        return false
    }
}

// MARK: - LocationInferer

/// Mirrors normalizeLocationFromSource() from server/extract.js.
/// Pure functions — no I/O, no SwiftData.
public enum LocationInferer {
    // MARK: - Public entry point

    public static func normalize(extracted: [String: Any?], description: String?) -> [String: Any?] {
        let remoteLocation = remoteLocationFromSource(description)
        let loc = (extracted["location"] as? String)?.trimmingCharacters(in: .whitespaces) ?? ""
        let isBareCountry = loc.range(
            of: #"^(USA|United States|U\.S\.A?\.?|US)$"#,
            options: [.regularExpression, .caseInsensitive]
        ) != nil

        if let remoteLocation, loc.isEmpty || loc.lowercased() == "remote" || isBareCountry {
            var out = extracted
            out["location"] = remoteLocation as Any?
            return out
        }
        if extracted["location"] is String, !loc.isEmpty { return extracted }

        if let location = sourceLocationFromTitle(description, title: extracted["title"] as? String) {
            var out = extracted
            out["location"] = location as Any?
            return out
        }
        if RemoteTypeInferer.sourceIndicatesRemote(description) {
            var out = extracted
            out["location"] = "Remote" as Any?
            return out
        }
        return extracted
    }

    // MARK: - Helpers

    static func remoteLocationFromSource(_ description: String?) -> String? {
        let text = description ?? ""
        let pattern = #"^Remote(?:\s*[-–—]\s*((?:United States|USA|U\.S\.|US)(?:\s+or\s+[A-Za-z]+)?))?\b"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.anchorsMatchLines, .caseInsensitive]),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) else { return nil }
        let nsText = text as NSString
        let g1Range = match.range(at: 1)
        if g1Range.location != NSNotFound && g1Range.length > 0 {
            return "Remote - " + nsText.substring(with: g1Range).trimmingCharacters(in: .whitespaces)
        }
        return "Remote"
    }

    static func locationFromBasedIn(_ description: String?) -> String? {
        let text = description ?? ""
        let pattern = #"\b(?:hybrid|remote|onsite|on-site)\s+role\s+based\s+in\s+([^.\n(]+?)(?:\s*\(|\.|\n|$)"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) else { return nil }
        let nsText = text as NSString
        return nsText.substring(with: match.range(at: 1)).trimmingCharacters(in: .whitespaces).replacingOccurrences(
            of: #"\s*,\s*$"#,
            with: "",
            options: .regularExpression
        )
    }

    static func metadataValue(_ lines: [String], label: String) -> String? {
        let prefix = label.lowercased() + ":"
        for line in lines {
            guard line.lowercased().hasPrefix(prefix) else { continue }
            let value = String(line.dropFirst(prefix.count)).trimmingCharacters(in: .whitespaces)
            if !value.isEmpty { return value }
        }
        return nil
    }

    static func sourceLocationFromTitle(_ description: String?, title: String?) -> String? {
        guard let title, !title.isEmpty else { return nil }
        let lines = (description ?? "").components(separatedBy: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        let normalizedTitle = title.trimmingCharacters(in: .whitespaces).lowercased()

        if let metaLoc = metadataValue(lines, label: "Location") { return metaLoc }
        if let basedIn = locationFromBasedIn(description) { return basedIn }

        // dropLast() instead of 0..<(count-1): an empty `lines` would make count-1 == -1 and trap
        // the Range (TASK-475). dropLast() yields an empty range for 0/1 lines.
        for idx in lines.indices.dropLast() {
            guard lines[idx].lowercased() == normalizedTitle else { continue }
            let candidate = lines[idx + 1]
            // Match "City, State + N more" pattern (Microsoft style)
            if candidate.range(of: #"\bUnited States\b"#, options: .regularExpression) != nil && candidate
                .contains(",") {
                return candidate.replacingOccurrences(of: #"\s+\+\s*"#, with: " + ", options: .regularExpression)
            }
            // Match "City, ST" pattern
            if candidate.range(of: #"^[A-Z][A-Za-z .'-]+,\s*[A-Z]{2}\b"#, options: .regularExpression) != nil {
                return candidate
            }
        }
        return nil
    }
}

// MARK: - CompanyBackfiller

/// Mirrors normalizeCompanyFromSource() from server/extract.js.
/// Pure functions — no I/O, no SwiftData.
public enum CompanyBackfiller {
    /// Returns updated extracted dict with company filled from JSON-LD if originally nil.
    public static func normalize(extracted: [String: Any?], description: String?) -> [String: Any?] {
        if let company = extracted["company"] as? String, !company.isEmpty { return extracted }
        guard let company = structuredHiringOrganizationName(description) else { return extracted }
        var out = extracted
        out["company"] = company as Any?
        return out
    }

    static func structuredHiringOrganizationName(_ description: String?) -> String? {
        let text = description ?? ""
        let pattern = #""hiringOrganization"\s*:\s*\{[\s\S]{0,1000}?"name"\s*:\s*"([^"]+)""#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) else { return nil }
        return (text as NSString).substring(with: match.range(at: 1))
    }
}

// MARK: - DisplayNormalizer

/// Mirrors mapStatus/mapRemote/mapEmployment/mapExtractionStatus from static/transform.js.
public enum DisplayNormalizer {
    public static func mapStatus(_ statusStr: String?) -> String {
        guard let statusStr else { return "" }
        let map: [String: String] = [
            "new": "new",
            "saved": "pursuing", "interested": "pursuing", "pursuing": "pursuing",
            "applied": "applied",
            "interviewing": "interview",
            "offer": "offer",
            "rejected": "rejected",
            "ignored": "passed", "passed": "passed",
            "closed": "closed",
            "archived": "archived",
            "duplicate": "duplicate"
        ]
        return map[statusStr] ?? statusStr
    }

    public static func mapRemote(_ remoteStr: String?) -> String {
        guard let remoteStr, !remoteStr.isEmpty else { return "—" }
        let map: [String: String] = ["remote": "Remote", "hybrid": "Hybrid", "onsite": "Onsite", "unknown": "—"]
        return map[remoteStr] ?? remoteStr
    }

    public static func mapEmployment(_ raw: String?) -> String {
        guard let raw, !raw.isEmpty else { return "—" }
        let map: [String: String] = [
            "full_time": "Full-time", "fulltime": "Full-time", "full-time": "Full-time",
            "part_time": "Part-time", "parttime": "Part-time", "part-time": "Part-time",
            "contract": "Contract", "contractor": "Contract",
            "freelance": "Freelance", "internship": "Internship", "intern": "Internship",
            "temporary": "Temporary", "temp": "Temporary"
        ]
        let key = raw.lowercased().replacingOccurrences(of: " ", with: "_")
        if let mappedValue = map[key] { return mappedValue }
        if let mappedValue = map[raw.lowercased()] { return mappedValue }
        return raw.prefix(1).uppercased() + raw.dropFirst()
    }

    public static func mapExtractionStatus(_ status: String?) -> String {
        if status == "succeeded" { return "ok" }
        if status == "failed" { return "fail" }
        return "pending"
    }

    /// Convert a string or [String] to [String]. Mirrors toStringArray() from transform.js.
    public static func toStringArray(_ value: Any?) -> [String] {
        if let arr = value as? [String] { return arr }
        if let arr = value as? [Any] { return arr.compactMap { $0 as? String } }
        if let str = value as? String { return str.isEmpty ? [] : [str] }
        guard let value else { return [] }
        return [String(describing: value)]
    }
}

// MARK: - JobFieldNormalizer

/// Composes SalaryNormalizer, RemoteTypeInferer, LocationInferer, CompanyBackfiller.
/// Takes a raw extracted dict + source capture context → normalized field values.
public struct JobFieldNormalizer {
    public init() {}

    /// Run all normalization passes and return the final normalized dict.
    public func normalize(
        extracted: [String: Any?],
        sourceText: String? = nil,
        url: String? = nil,
        preferredLocations: String? = nil
    ) -> [String: Any?] {
        var result = extracted
        result = SalaryNormalizer.normalize(
            extracted: result,
            preferredLocations: preferredLocations,
            sourceText: sourceText
        )
        result = CompanyBackfiller.normalize(extracted: result, description: sourceText)
        result = LocationInferer.normalize(extracted: result, description: sourceText)
        result = RemoteTypeInferer.normalize(extracted: result, description: sourceText, url: url)
        return result
    }
}

// swiftlint:enable line_length function_body_length
// swiftlint:enable type_body_length
