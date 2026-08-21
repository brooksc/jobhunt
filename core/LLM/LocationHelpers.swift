import Foundation

// MARK: - Shared location helpers

// Extracted from Normalization.swift, which had grown past the 800-line limit. These are the pieces
// several types share — the state tables, preferred-location parsing, and the match normalizer that
// `RemoteGeography`, `LocationCriteria` and the inferers all depend on — so they belong somewhere
// their users can find them rather than at the bottom of the salary/remote-type file.

private let stateAbbrevToName: [String: String] = [
    "al": "alabama", "ak": "alaska", "az": "arizona", "ar": "arkansas", "ca": "california",
    "co": "colorado", "ct": "connecticut", "de": "delaware", "dc": "district of columbia",
    "fl": "florida", "ga": "georgia", "hi": "hawaii", "id": "idaho", "il": "illinois",
    "in": "indiana", "ia": "iowa", "ks": "kansas", "ky": "kentucky", "la": "louisiana",
    "me": "maine", "md": "maryland", "ma": "massachusetts", "mi": "michigan", "mn": "minnesota",
    "ms": "mississippi", "mo": "missouri", "mt": "montana", "ne": "nebraska", "nv": "nevada",
    "nh": "new hampshire", "nj": "new jersey", "nm": "new mexico", "ny": "new york",
    "nc": "north carolina", "nd": "north dakota", "oh": "ohio", "ok": "oklahoma", "or": "oregon",
    "pa": "pennsylvania", "ri": "rhode island", "sc": "south carolina", "sd": "south dakota",
    "tn": "tennessee", "tx": "texas", "ut": "utah", "vt": "vermont", "va": "virginia",
    "wa": "washington", "wv": "west virginia", "wi": "wisconsin", "wy": "wyoming"
]
/// Internal (not file-private) so `RemoteGeography` can build its US-token set from the same table.
let stateNameToAbbrev: [String: String] = Dictionary(uniqueKeysWithValues: stateAbbrevToName.map { abbr, name in
    (
        name,
        abbr
    )
})

func parsePreferredLocations(_ preferredLocations: String?) -> [String] {
    guard let pref = preferredLocations, !pref.isEmpty else { return [] }
    var terms: [String] = []
    var seen = Set<String>()
    for raw in pref.split(separator: ",") {
        let token = raw.trimmingCharacters(in: .whitespaces)
        if token.isEmpty { continue }
        let base = token.lowercased()
        if seen.contains(base) { continue }
        terms.append(token)
        seen.insert(base)
        // Expand abbreviation → full name
        if let full = stateAbbrevToName[base], !seen.contains(full) {
            let capitalized = full.prefix(1).uppercased() + full.dropFirst()
            terms.append(capitalized)
            seen.insert(full)
        }
        // Expand full name → abbreviation
        if let abbr = stateNameToAbbrev[base], !seen.contains(abbr) {
            terms.append(abbr.uppercased())
            seen.insert(abbr)
        }
    }
    return terms
}

func normalizeForMatch(_ value: String) -> String {
    value.lowercased().replacingOccurrences(of: #"[^a-z0-9]+"#, with: " ", options: .regularExpression)
        .trimmingCharacters(in: .whitespaces)
}

func termMatches(_ location: String, term: String) -> Bool {
    let haystack = normalizeForMatch(location)
    let needle = normalizeForMatch(term)
    guard !needle.isEmpty else { return false }
    if needle.count == 2 {
        // State abbreviation — word-boundary match
        let pattern = "\\b\(NSRegularExpression.escapedPattern(for: needle))\\b"
        return haystack.range(of: pattern, options: .regularExpression) != nil
    }
    return haystack.contains(needle)
}
