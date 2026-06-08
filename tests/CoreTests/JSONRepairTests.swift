// swiftlint:disable force_unwrapping
// JSONRepairTests.swift — tests for JSONRepair utility
import XCTest
@testable import JobhuntCore

final class JSONRepairTests: XCTestCase {

    // MARK: - extractJSON

    func testExtractJSONStripsJsonFence() {
        let input = "```json\n{\"key\": \"value\"}\n```"
        XCTAssertEqual(extractJSON(input), "{\"key\": \"value\"}")
    }

    func testExtractJSONStripsPlainFence() {
        let input = "```\n{\"key\": \"value\"}\n```"
        XCTAssertEqual(extractJSON(input), "{\"key\": \"value\"}")
    }

    func testExtractJSONPassesThroughPlainJSON() {
        let input = "{\"key\": \"value\"}"
        XCTAssertEqual(extractJSON(input), "{\"key\": \"value\"}")
    }

    // MARK: - repairJSON: trailing commas

    func testRepairRemovesTrailingCommaInObject() throws {
        let input = "{\"key\": \"value\",}"
        let result = try repairJSON(input)
        let data = result.data(using: .utf8)!
        XCTAssertNotNil(try? JSONSerialization.jsonObject(with: data))
    }

    func testRepairRemovesTrailingCommaInArray() throws {
        let input = "[1, 2, 3,]"
        let result = try repairJSON(input)
        let data = result.data(using: .utf8)!
        XCTAssertNotNil(try? JSONSerialization.jsonObject(with: data))
    }

    func testRepairRemovesTrailingCommaWithWhitespace() throws {
        let input = "{\n  \"a\": 1,\n  \"b\": 2,\n}"
        let result = try repairJSON(input)
        let data = result.data(using: .utf8)!
        XCTAssertNotNil(try? JSONSerialization.jsonObject(with: data))
    }

    // MARK: - repairJSON: unquoted keys

    func testRepairQuotesUnquotedKeys() throws {
        let input = "{name: \"Alice\", age: 30}"
        let result = try repairJSON(input)
        let data = result.data(using: .utf8)!
        let obj = (try JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        XCTAssertEqual(obj["name"] as? String, "Alice")
        XCTAssertEqual(obj["age"] as? Int, 30)
    }

    // MARK: - repairJSON: single quotes

    func testRepairConvertsSingleQuotedStrings() throws {
        let input = "{'key': 'value'}"
        let result = try repairJSON(input)
        let data = result.data(using: .utf8)!
        let obj = (try JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        XCTAssertEqual(obj["key"] as? String, "value")
    }

    // MARK: - repairJSON: fenced blocks

    func testRepairHandlesFencedJsonBlock() throws {
        let input = "```json\n{\"title\": \"Engineer\", \"salary\": 100000}\n```"
        let result = try repairJSON(input)
        let data = result.data(using: .utf8)!
        let obj = (try JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        XCTAssertEqual(obj["title"] as? String, "Engineer")
    }

    // MARK: - repairJSON: valid JSON passes through

    func testRepairPassesThroughValidJSON() throws {
        let input = "{\"a\": 1, \"b\": [1, 2, 3]}"
        let result = try repairJSON(input)
        let data = result.data(using: .utf8)!
        XCTAssertNotNil(try? JSONSerialization.jsonObject(with: data))
    }

    // MARK: - repairJSON: combined

    func testRepairHandlesCombinedIssues() throws {
        // Fenced + trailing comma + unquoted key
        let input = "```json\n{name: 'Alice', age: 30,}\n```"
        let result = try repairJSON(input)
        let data = result.data(using: .utf8)!
        let obj = (try JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        XCTAssertEqual(obj["name"] as? String, "Alice")
    }
}

// swiftlint:enable force_unwrapping
