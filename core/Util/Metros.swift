// Metros.swift — port of server/metros.js
// Pure Foundation only — no SwiftUI/AppKit/SwiftData imports.

import Foundation

// MARK: - Data structures

public struct MetroInfo: Sendable {
    public let label: String
    public let cities: [String]
    public init(label: String, cities: [String]) {
        self.label = label
        self.cities = cities
    }
}

public struct StateInfo: Sendable {
    public let label: String
    public let metros: [String: MetroInfo]
    public init(label: String, metros: [String: MetroInfo]) {
        self.label = label
        self.metros = metros
    }
}

public struct ParsedMetro: Sendable, Equatable {
    public let state: String
    public let metro: String
    public init(state: String, metro: String) {
        self.state = state
        self.metro = metro
    }
}

// MARK: - Metro data (mirrors metros.js METRO_DATA)

public let metroData: [String: StateInfo] = [
    "wa": StateInfo(label: "Washington", metros: [
        "seattle": MetroInfo(label: "Seattle Metro", cities: ["Seattle","Bellevue","Redmond","Kirkland","Bothell","Renton","Issaquah","Sammamish","Kent","Federal Way","Shoreline","Kenmore","Woodinville","Mercer Island"]),
        "spokane": MetroInfo(label: "Spokane", cities: ["Spokane","Spokane Valley","Liberty Lake"]),
    ]),
    "ca": StateInfo(label: "California", metros: [
        "bay-area": MetroInfo(label: "SF Bay Area", cities: ["San Francisco","San Jose","Oakland","Sunnyvale","Santa Clara","Palo Alto","Mountain View","Menlo Park","Cupertino","Fremont","Berkeley","Redwood City","Foster City","San Mateo","Burlingame","South San Francisco","Emeryville","Walnut Creek","San Ramon","Pleasanton","Concord","Dublin"]),
        "la": MetroInfo(label: "Los Angeles Metro", cities: ["Los Angeles","Santa Monica","Culver City","El Segundo","Playa Vista","Long Beach","Burbank","Glendale","Pasadena","Irvine","Manhattan Beach","Hermosa Beach","Redondo Beach","Torrance","El Segundo","West Hollywood","Beverly Hills","Marina del Rey"]),
        "san-diego": MetroInfo(label: "San Diego", cities: ["San Diego","La Jolla","Carlsbad","Solana Beach","Del Mar","Chula Vista","El Cajon"]),
        "sacramento": MetroInfo(label: "Sacramento", cities: ["Sacramento","Roseville","Folsom","Elk Grove","Davis","Rancho Cordova"]),
    ]),
    "tx": StateInfo(label: "Texas", metros: [
        "austin": MetroInfo(label: "Austin", cities: ["Austin","Round Rock","Cedar Park","Georgetown","Pflugerville","Kyle","Buda","Leander","San Marcos"]),
        "dallas-fort-worth": MetroInfo(label: "Dallas–Fort Worth", cities: ["Dallas","Fort Worth","Plano","Irving","Frisco","Allen","McKinney","Richardson","Garland","Addison","Carrollton","Grapevine","Southlake","Arlington","Flower Mound"]),
        "houston": MetroInfo(label: "Houston", cities: ["Houston","Sugar Land","The Woodlands","Pearland","Katy","Stafford","Clear Lake"]),
        "san-antonio": MetroInfo(label: "San Antonio", cities: ["San Antonio","New Braunfels","Boerne","Schertz"]),
    ]),
    "ny": StateInfo(label: "New York", metros: [
        "nyc": MetroInfo(label: "NYC Metro", cities: ["New York","Manhattan","Brooklyn","Queens","Bronx","Staten Island","Jersey City","Newark","Hoboken","White Plains","Yonkers","Stamford"]),
        "albany": MetroInfo(label: "Albany", cities: ["Albany","Troy","Schenectady"]),
    ]),
    "ma": StateInfo(label: "Massachusetts", metros: [
        "boston": MetroInfo(label: "Boston Metro", cities: ["Boston","Cambridge","Somerville","Waltham","Lexington","Burlington","Woburn","Malden","Quincy","Needham","Weston","Framingham","Natick"]),
    ]),
    "il": StateInfo(label: "Illinois", metros: [
        "chicago": MetroInfo(label: "Chicago Metro", cities: ["Chicago","Evanston","Naperville","Schaumburg","Oak Park","Lisle","Downers Grove","Rosemont","Skokie","Hoffman Estates"]),
    ]),
    "or": StateInfo(label: "Oregon", metros: [
        "portland": MetroInfo(label: "Portland Metro", cities: ["Portland","Beaverton","Hillsboro","Lake Oswego","Tigard","Vancouver","Gresham","Tualatin"]),
    ]),
    "co": StateInfo(label: "Colorado", metros: [
        "denver": MetroInfo(label: "Denver Metro", cities: ["Denver","Boulder","Aurora","Lakewood","Arvada","Westminster","Broomfield","Englewood","Centennial","Greenwood Village","Littleton"]),
    ]),
    "ga": StateInfo(label: "Georgia", metros: [
        "atlanta": MetroInfo(label: "Atlanta Metro", cities: ["Atlanta","Alpharetta","Marietta","Sandy Springs","Smyrna","Roswell","Johns Creek","Norcross","Peachtree City","Duluth"]),
    ]),
    "va": StateInfo(label: "Virginia", metros: [
        "northern-va": MetroInfo(label: "Northern Virginia", cities: ["Arlington","Alexandria","Reston","Herndon","McLean","Tysons","Fairfax","Sterling","Chantilly","Ashburn","Vienna"]),
        "richmond": MetroInfo(label: "Richmond", cities: ["Richmond","Henrico","Chesterfield"]),
    ]),
    "nc": StateInfo(label: "North Carolina", metros: [
        "research-triangle": MetroInfo(label: "Research Triangle", cities: ["Raleigh","Durham","Chapel Hill","Cary","Morrisville","Apex","Holly Springs"]),
        "charlotte": MetroInfo(label: "Charlotte", cities: ["Charlotte","Concord","Gastonia","Matthews","Huntersville"]),
    ]),
    "fl": StateInfo(label: "Florida", metros: [
        "miami": MetroInfo(label: "Miami Metro", cities: ["Miami","Fort Lauderdale","Boca Raton","West Palm Beach","Coral Gables","Doral","Aventura"]),
        "orlando": MetroInfo(label: "Orlando", cities: ["Orlando","Lake Mary","Maitland","Winter Park","Oviedo"]),
        "tampa": MetroInfo(label: "Tampa Bay", cities: ["Tampa","St. Petersburg","Clearwater","Sarasota"]),
        "jacksonville": MetroInfo(label: "Jacksonville", cities: ["Jacksonville"]),
    ]),
    "az": StateInfo(label: "Arizona", metros: [
        "phoenix": MetroInfo(label: "Phoenix Metro", cities: ["Phoenix","Scottsdale","Tempe","Mesa","Chandler","Gilbert","Glendale","Peoria","Surprise"]),
        "tucson": MetroInfo(label: "Tucson", cities: ["Tucson"]),
    ]),
    "ut": StateInfo(label: "Utah", metros: [
        "salt-lake-city": MetroInfo(label: "Salt Lake City / Utah Valley", cities: ["Salt Lake City","Provo","Orem","Lehi","American Fork","Draper","Sandy","South Jordan","Murray","Lindon","Pleasant Grove"]),
    ]),
    "oh": StateInfo(label: "Ohio", metros: [
        "columbus": MetroInfo(label: "Columbus", cities: ["Columbus","Dublin","Westerville","New Albany","Grove City"]),
        "cleveland": MetroInfo(label: "Cleveland", cities: ["Cleveland","Beachwood","Independence","Solon","Strongsville"]),
        "cincinnati": MetroInfo(label: "Cincinnati", cities: ["Cincinnati","Blue Ash","Mason","Covington"]),
    ]),
    "pa": StateInfo(label: "Pennsylvania", metros: [
        "philadelphia": MetroInfo(label: "Philadelphia Metro", cities: ["Philadelphia","King of Prussia","Wayne","Malvern","Radnor","Horsham","Blue Bell","Conshohocken"]),
        "pittsburgh": MetroInfo(label: "Pittsburgh", cities: ["Pittsburgh","Cranberry Township","Canonsburg"]),
    ]),
    "nj": StateInfo(label: "New Jersey", metros: [
        "northern-nj": MetroInfo(label: "Northern NJ", cities: ["Hoboken","Jersey City","Newark","Parsippany","Florham Park","Basking Ridge","Bridgewater","Princeton"]),
    ]),
    "md": StateInfo(label: "Maryland", metros: [
        "dc-metro": MetroInfo(label: "DC / Baltimore Metro", cities: ["Baltimore","Columbia","Bethesda","Rockville","Silver Spring","Gaithersburg","Annapolis","Chevy Chase","Greenbelt"]),
    ]),
    "mi": StateInfo(label: "Michigan", metros: [
        "detroit": MetroInfo(label: "Detroit Metro", cities: ["Detroit","Ann Arbor","Dearborn","Troy","Southfield","Royal Oak","Auburn Hills","Livonia","Grand Rapids"]),
    ]),
    "mn": StateInfo(label: "Minnesota", metros: [
        "minneapolis": MetroInfo(label: "Minneapolis–St. Paul", cities: ["Minneapolis","St. Paul","Bloomington","Eden Prairie","Edina","Plymouth","Minnetonka","Maple Grove","Richfield"]),
    ]),
]

// State abbreviation → full name
public let stateAbbrevToFull: [String: String] = [
    "wa": "Washington", "ca": "California", "tx": "Texas", "ny": "New York",
    "ma": "Massachusetts", "il": "Illinois", "or": "Oregon", "co": "Colorado",
    "ga": "Georgia", "va": "Virginia", "nc": "North Carolina", "fl": "Florida",
    "az": "Arizona", "ut": "Utah", "oh": "Ohio", "pa": "Pennsylvania",
    "nj": "New Jersey", "md": "Maryland", "mi": "Michigan", "mn": "Minnesota",
]

// MARK: - Functions

/// Parses a comma-separated "state:metro" preference string.
///
/// Mirrors metros.js `parsePreferredMetros`.
///
/// Example: `"wa:seattle,ca:bay-area"` → `[ParsedMetro(state:"wa", metro:"seattle"), ...]`
public func parsePreferredMetros(_ str: String?) -> [ParsedMetro] {
    guard let str, !str.isEmpty else { return [] }
    return str.split(separator: ",")
        .map { $0.trimmingCharacters(in: .whitespaces) }
        .filter { !$0.isEmpty }
        .compactMap { token -> ParsedMetro? in
            let parts = token.split(separator: ":", maxSplits: 1)
            guard parts.count == 2 else { return nil }
            let state = String(parts[0]).lowercased()
            let metro = String(parts[1]).lowercased()
            guard !state.isEmpty, !metro.isEmpty else { return nil }
            return ParsedMetro(state: state, metro: metro)
        }
}

/// Expands a metro preference string to a deduplicated list of city/state names.
///
/// Mirrors metros.js `expandMetros`.
public func expandMetros(_ str: String?) -> [String] {
    guard let str, !str.isEmpty else { return [] }
    var seen = Set<String>()
    var result: [String] = []

    let add: (String) -> Void = { v in
        let key = v.lowercased()
        if !seen.contains(key) {
            seen.insert(key)
            result.append(v)
        }
    }

    let parsed = parsePreferredMetros(str)
    var addedStates = Set<String>()

    for item in parsed {
        guard let stateData = metroData[item.state] else { continue }
        guard let metroInfo = stateData.metros[item.metro] else { continue }

        for city in metroInfo.cities { add(city) }

        if !addedStates.contains(item.state) {
            addedStates.insert(item.state)
            add(item.state.uppercased())
            if let fullName = stateAbbrevToFull[item.state] {
                add(fullName)
            }
        }
    }

    return result
}
