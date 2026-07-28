import Foundation

/// Whether a *remote* posting's location is somewhere the user can actually work.
///
/// `LocationCriteria` historically short-circuited on `.remote` — "remote ignores preferred
/// locations" — so a posting extracted as remote met the criteria no matter where remote was
/// offered. That let Europe-only roles (job #341, Nebius, "Amsterdam") sit in Interested looking
/// qualified, with no way to filter them out.
///
/// The classification is deliberately asymmetric: a location is only ruled **out of bounds** when it
/// positively names foreign places and names nothing the user is eligible for. Anything unrecognised
/// stays `indeterminate` and continues to pass, because wrongly demoting a good job is far more
/// costly here than letting an unqualified one through — the user still reviews the list.
public enum RemoteGeography {
    public enum Verdict: Equatable {
        /// Names a place the user matches (a preferred term, or a US locale).
        case eligible
        /// Names foreign places only — the user cannot work here.
        case outOfBounds
        /// No usable signal ("Global", "Multiple Locations", ""). Treated as eligible by callers.
        case indeterminate
    }

    public static func classify(location: String?, preferredTerms: [String]) -> Verdict {
        let raw = location ?? ""
        let haystack = normalizeForMatch(raw)
        guard !haystack.isEmpty else { return .indeterminate }

        if preferredTerms.contains(where: { termMatches(raw, term: $0) }) { return .eligible }
        // Eligibility wins over a foreign hit, so a multi-region posting ("EMEA and AMER time
        // zones", "Toronto, San Francisco, London") is not mistaken for a foreign-only one.
        if contains(haystack, anyOf: usTokens) { return .eligible }
        if contains(haystack, anyOf: foreignTokens) { return .outOfBounds }
        return .indeterminate
    }

    /// Word-boundary matching throughout — a substring test would let "Austria" satisfy "us" and
    /// "Indiana" satisfy "india".
    private static func contains(_ haystack: String, anyOf tokens: Set<String>) -> Bool {
        let words = haystack.split(separator: " ").map(String.init)
        guard !words.isEmpty else { return false }
        // Single words plus the 2- and 3-word phrases ("united states", "new zealand", "tel aviv").
        var phrases = Set(words)
        for size in 2 ... 3 where words.count >= size {
            for start in 0 ... (words.count - size) {
                phrases.insert(words[start ..< (start + size)].joined(separator: " "))
            }
        }
        return !phrases.isDisjoint(with: tokens)
    }

    /// US states (name + abbreviation) come from the existing normalization tables so the two can't
    /// drift; the rest are national/regional words and the metros most common in postings.
    private static let usTokens: Set<String> = {
        var tokens: Set = [
            "us", "u s", "usa", "united states", "america", "americas", "amer", "north america",
            "nationwide", "anywhere in the us", "conus",
            "san francisco", "bay area", "silicon valley", "new york", "nyc", "brooklyn",
            "los angeles", "san diego", "san jose", "seattle", "bellevue", "portland", "denver",
            "boulder", "austin", "dallas", "houston", "chicago", "boston", "cambridge ma",
            "atlanta", "miami", "orlando", "tampa", "philadelphia", "pittsburgh", "detroit",
            "minneapolis", "phoenix", "las vegas", "salt lake city", "nashville", "charlotte",
            "raleigh", "washington dc", "arlington va", "baltimore", "st louis", "kansas city",
            "columbus", "cleveland", "indianapolis", "milwaukee", "sacramento", "honolulu",
            "anchorage", "albuquerque", "oklahoma city", "new orleans", "louisville", "memphis"
        ]
        for (name, abbr) in stateNameToAbbrev {
            tokens.insert(normalizeForMatch(name))
            tokens.insert(normalizeForMatch(abbr))
        }
        return tokens
    }()

    /// Countries, regional shorthands, and unambiguous foreign metros. Names that collide with a US
    /// place are deliberately absent (Ontario CA, Vienna VA, Manchester NH, Birmingham AL) — the US
    /// pass runs first, but leaving them out means an unqualified string lands on `indeterminate`
    /// rather than a wrong `outOfBounds`.
    private static let foreignTokens: Set<String> = [
        // Regions
        "emea", "apac", "latam", "europe", "european union", "eu", "eea", "asia", "asia pacific",
        "middle east", "africa", "latin america", "south america", "oceania",
        // Americas (non-US)
        "canada", "toronto", "vancouver", "montreal", "calgary", "mexico", "mexico city",
        "guadalajara", "brazil", "sao paulo", "rio de janeiro", "argentina", "buenos aires",
        "colombia", "bogota", "medellin", "chile", "santiago", "peru", "lima", "uruguay",
        "costa rica", "guatemala",
        // Europe
        "united kingdom", "uk", "england", "scotland", "wales", "london", "edinburgh", "glasgow",
        "ireland", "dublin", "france", "paris", "lyon", "germany", "berlin", "munich", "hamburg",
        "netherlands", "amsterdam", "rotterdam", "utrecht", "belgium", "brussels", "spain",
        "madrid", "barcelona", "valencia", "portugal", "lisbon", "porto", "italy", "rome", "milan",
        "switzerland", "zurich", "geneva", "austria", "poland", "warsaw", "krakow", "wroclaw",
        "czech republic", "czechia", "prague", "slovakia", "hungary", "budapest", "romania",
        "bucharest", "bulgaria", "sofia", "greece", "athens", "croatia", "serbia", "belgrade",
        "ukraine", "kyiv", "kiev", "lviv", "estonia", "tallinn", "latvia", "riga", "lithuania",
        "vilnius", "sweden", "stockholm", "norway", "oslo", "denmark", "copenhagen", "finland",
        "helsinki", "iceland", "reykjavik", "luxembourg", "malta", "cyprus", "turkey", "istanbul",
        // Middle East / Africa
        "israel", "tel aviv", "jerusalem", "uae", "united arab emirates", "dubai", "abu dhabi",
        "saudi arabia", "riyadh", "qatar", "doha", "egypt", "cairo", "morocco", "casablanca",
        "nigeria", "lagos", "kenya", "nairobi", "ghana", "accra", "south africa", "cape town",
        "johannesburg",
        // Asia / Pacific
        "india", "bangalore", "bengaluru", "hyderabad", "mumbai", "new delhi", "gurgaon",
        "gurugram", "noida", "pune", "chennai", "china", "beijing", "shanghai", "shenzhen",
        "guangzhou", "hong kong", "taiwan", "taipei", "japan", "tokyo", "osaka", "south korea",
        "seoul", "singapore", "malaysia", "kuala lumpur", "indonesia", "jakarta", "thailand",
        "bangkok", "vietnam", "hanoi", "ho chi minh city", "philippines", "manila", "cebu",
        "pakistan", "karachi", "lahore", "bangladesh", "dhaka", "sri lanka", "nepal",
        "australia", "sydney", "melbourne", "brisbane", "perth", "new zealand", "auckland",
        "wellington"
    ]
}
