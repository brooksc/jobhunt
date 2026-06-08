// MetrosTests.swift — tests for Metros utility
import XCTest
@testable import JobhuntCore

final class MetrosTests: XCTestCase {

    // MARK: - parsePreferredMetros

    func testParsePreferredMetrosReturnsEmptyForNil() {
        XCTAssertEqual(parsePreferredMetros(nil), [])
    }

    func testParsePreferredMetrosReturnsEmptyForEmptyString() {
        XCTAssertEqual(parsePreferredMetros(""), [])
    }

    func testParsePreferredMetrosParsesSimpleEntry() {
        let result = parsePreferredMetros("wa:seattle")
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].state, "wa")
        XCTAssertEqual(result[0].metro, "seattle")
    }

    func testParsePreferredMetrosParsesMultipleEntries() {
        let result = parsePreferredMetros("wa:seattle,ca:bay-area")
        XCTAssertEqual(result.count, 2)
        XCTAssertEqual(result[0], ParsedMetro(state: "wa", metro: "seattle"))
        XCTAssertEqual(result[1], ParsedMetro(state: "ca", metro: "bay-area"))
    }

    func testParsePreferredMetrosTrimsWhitespace() {
        let result = parsePreferredMetros("wa:seattle , ca:bay-area")
        XCTAssertEqual(result.count, 2)
    }

    func testParsePreferredMetrosLowercasesStateAndMetro() {
        let result = parsePreferredMetros("WA:Seattle")
        XCTAssertEqual(result[0].state, "wa")
        XCTAssertEqual(result[0].metro, "seattle")
    }

    // MARK: - expandMetros

    func testExpandMetrosReturnsEmptyForNil() {
        XCTAssertEqual(expandMetros(nil), [])
    }

    func testExpandMetrosReturnsEmptyForEmptyString() {
        XCTAssertEqual(expandMetros(""), [])
    }

    func testExpandMetrosIncludesCities() {
        let result = expandMetros("wa:seattle")
        XCTAssertTrue(result.contains("Seattle"))
        XCTAssertTrue(result.contains("Bellevue"))
        XCTAssertTrue(result.contains("Redmond"))
    }

    func testExpandMetrosIncludesStateAbbrevAndFullName() {
        let result = expandMetros("wa:seattle")
        XCTAssertTrue(result.contains("WA"), "state abbreviation should be included")
        XCTAssertTrue(result.contains("Washington"), "full state name should be included")
    }

    func testExpandMetrosDeduplicatesCities() {
        // Seattle appears only once even with multiple metros that overlap (none in this data, but verify no dups)
        let result = expandMetros("wa:seattle")
        let seattleCount = result.filter { $0 == "Seattle" }.count
        XCTAssertEqual(seattleCount, 1)
    }

    func testExpandMetrosHandlesMultipleMetros() {
        let result = expandMetros("wa:seattle,ca:bay-area")
        XCTAssertTrue(result.contains("Seattle"))
        XCTAssertTrue(result.contains("San Francisco"))
        XCTAssertTrue(result.contains("WA"))
        XCTAssertTrue(result.contains("Washington"))
        XCTAssertTrue(result.contains("CA"))
        XCTAssertTrue(result.contains("California"))
    }

    func testExpandMetrosAddsStateOnceForMultipleMetrosInSameState() {
        let result = expandMetros("ca:bay-area,ca:la")
        let caCount = result.filter { $0 == "CA" }.count
        XCTAssertEqual(caCount, 1, "State abbreviation added only once per state")
        let californiaCount = result.filter { $0 == "California" }.count
        XCTAssertEqual(californiaCount, 1, "Full state name added only once per state")
    }

    func testExpandMetrosIgnoresUnknownState() {
        let result = expandMetros("xx:unknown")
        XCTAssertEqual(result, [])
    }

    func testExpandMetrosIgnoresUnknownMetro() {
        let result = expandMetros("wa:nonexistent")
        XCTAssertEqual(result, [])
    }

    // MARK: - metroData

    func testMetroDataContainsSeattle() {
        XCTAssertNotNil(metroData["wa"]?.metros["seattle"])
        XCTAssertEqual(metroData["wa"]?.metros["seattle"]?.label, "Seattle Metro")
    }

    func testMetroDataContainsBayArea() {
        XCTAssertNotNil(metroData["ca"]?.metros["bay-area"])
        XCTAssertTrue(metroData["ca"]!.metros["bay-area"]!.cities.contains("San Francisco"))
    }

    func testStateAbbrevToFullMapping() {
        XCTAssertEqual(stateAbbrevToFull["wa"], "Washington")
        XCTAssertEqual(stateAbbrevToFull["ca"], "California")
        XCTAssertEqual(stateAbbrevToFull["ny"], "New York")
    }
}
