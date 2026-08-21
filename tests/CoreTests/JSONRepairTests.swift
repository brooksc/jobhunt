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
        let data = try XCTUnwrap(result.data(using: .utf8))
        XCTAssertNotNil(try? JSONSerialization.jsonObject(with: data))
    }

    func testRepairRemovesTrailingCommaInArray() throws {
        let input = "[1, 2, 3,]"
        let result = try repairJSON(input)
        let data = try XCTUnwrap(result.data(using: .utf8))
        XCTAssertNotNil(try? JSONSerialization.jsonObject(with: data))
    }

    func testRepairRemovesTrailingCommaWithWhitespace() throws {
        let input = "{\n  \"a\": 1,\n  \"b\": 2,\n}"
        let result = try repairJSON(input)
        let data = try XCTUnwrap(result.data(using: .utf8))
        XCTAssertNotNil(try? JSONSerialization.jsonObject(with: data))
    }

    // MARK: - repairJSON: unquoted keys

    func testRepairQuotesUnquotedKeys() throws {
        let input = "{name: \"Alice\", age: 30}"
        let result = try repairJSON(input)
        let data = try XCTUnwrap(result.data(using: .utf8))
        let obj = try (JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        XCTAssertEqual(obj["name"] as? String, "Alice")
        XCTAssertEqual(obj["age"] as? Int, 30)
    }

    // MARK: - repairJSON: single quotes

    func testRepairConvertsSingleQuotedStrings() throws {
        let input = "{'key': 'value'}"
        let result = try repairJSON(input)
        let data = try XCTUnwrap(result.data(using: .utf8))
        let obj = try (JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        XCTAssertEqual(obj["key"] as? String, "value")
    }

    // MARK: - repairJSON: fenced blocks

    func testRepairHandlesFencedJsonBlock() throws {
        let input = "```json\n{\"title\": \"Engineer\", \"salary\": 100000}\n```"
        let result = try repairJSON(input)
        let data = try XCTUnwrap(result.data(using: .utf8))
        let obj = try (JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        XCTAssertEqual(obj["title"] as? String, "Engineer")
    }

    // MARK: - repairJSON: valid JSON passes through

    func testRepairPassesThroughValidJSON() throws {
        let input = "{\"a\": 1, \"b\": [1, 2, 3]}"
        let result = try repairJSON(input)
        let data = try XCTUnwrap(result.data(using: .utf8))
        XCTAssertNotNil(try? JSONSerialization.jsonObject(with: data))
    }

    // MARK: - repairJSON: combined

    func testRepairHandlesCombinedIssues() throws {
        // Fenced + trailing comma + unquoted key
        let input = "```json\n{name: 'Alice', age: 30,}\n```"
        let result = try repairJSON(input)
        let data = try XCTUnwrap(result.data(using: .utf8))
        let obj = try (JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        XCTAssertEqual(obj["name"] as? String, "Alice")
    }

    // MARK: - TASK-267: Prose before/after JSON

    func testRepairProseBeforeJSON() throws {
        let input = "Here is the result:\n{\"company\":\"Acme\"}"
        let result = try repairJSON(input)
        let data = try XCTUnwrap(result.data(using: .utf8))
        let obj = try (JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        XCTAssertEqual(obj["company"] as? String, "Acme")
    }

    func testRepairProseAfterJSON() throws {
        let input = "{\"company\":\"Acme\"}\n\nLet me know if you need anything."
        let result = try repairJSON(input)
        let data = try XCTUnwrap(result.data(using: .utf8))
        let obj = try (JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        XCTAssertEqual(obj["company"] as? String, "Acme")
    }

    func testRepairProseBeforeAndAfterJSON() throws {
        let input = "Sure! Here you go:\n{\"company\":\"Acme\",\"score\":42}\n\nHope that helps!"
        let result = try repairJSON(input)
        let data = try XCTUnwrap(result.data(using: .utf8))
        let obj = try (JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        XCTAssertEqual(obj["company"] as? String, "Acme")
        XCTAssertEqual(obj["score"] as? Int, 42)
    }

    func testRepairMultipleJSONObjectsFails() {
        // Ambiguous: two top-level objects — extraction picks first-open to last-close,
        // producing invalid JSON, so repairJSON should throw.
        let input = "{\"a\":1}{\"b\":2}"
        XCTAssertThrowsError(try repairJSON(input))
    }

    // MARK: - TASK-166 / TASK-173: LocalizedError

    func testJSONRepairError_localizedDescription_doesNotLeakRawContent() {
        let rawContent = "THIS_IS_SECRET_CONTENT_THAT_MUST_NOT_APPEAR"
        let error = JSONRepairError.unparseable(rawContent)
        let desc = error.localizedDescription
        XCTAssertFalse(desc.contains(rawContent), "errorDescription must not expose raw model output")
        XCTAssertFalse(desc.isEmpty, "errorDescription must not be empty")
    }

    func testExtractionEngineError_invalidJSON_doesNotLeakRawOutput() {
        let rawOutput = "THIS_MUST_NOT_APPEAR_IN_DESCRIPTION"
        let error = ExtractionEngineError.invalidJSON(rawOutput)
        XCTAssertFalse(
            error.localizedDescription.contains(rawOutput),
            "invalidJSON errorDescription must not expose raw LLM output"
        )
        XCTAssertFalse(error.localizedDescription.isEmpty)
    }
}

/// The repair pass ran unconditionally and validated only afterwards, so it could turn a VALID model
/// response into an invalid one and report it as the model's fault. Job #861 failed ten times across
/// two captures because of it — Instacart's multi-state pay table contains `CA, NY:` inside a string,
/// and `quoteUnquotedKeys` treats that as an unquoted object key.
final class JSONRepairDoesNotBreakValidJSONTests: XCTestCase {
    private func parses(_ text: String) -> Bool {
        (try? JSONSerialization.jsonObject(with: Data(text.utf8))) != nil
    }

    /// The exact shape that broke job #861.
    func testMultiStatePayTableSurvives() throws {
        let raw = #"{"note": "CA, NY: $189,000—$199,500 USD; WA: $181,000"}"#
        XCTAssertTrue(parses(raw), "precondition: this is valid JSON")
        XCTAssertEqual(try repairJSON(raw), raw, "valid JSON must be returned untouched")
    }

    /// The general rule, not just that one string: anything already valid comes back byte-identical.
    func testValidJSONIsReturnedUnchanged() throws {
        let cases = [
            #"{"a": "colon: inside", "b": 1}"#,
            #"{"a": "it's an apostrophe"}"#,
            #"{"a": "trailing comma, inside a string,"}"#,
            #"{"a": "braces { } and brackets [ ] inside"}"#,
            #"{"a": "quote \" inside"}"#,
            #"{"list": ["x: 1", "y: 2"]}"#,
            #"{"a": "single 'quoted' words"}"#
        ]
        for raw in cases {
            XCTAssertTrue(parses(raw), "precondition failed for \(raw)")
            XCTAssertEqual(try repairJSON(raw), raw, "repair altered valid JSON: \(raw)")
        }
    }

    /// Fenced-but-valid JSON is unwrapped, and the JSON inside is still not otherwise touched.
    func testFencedValidJSONIsUnwrappedbutNotRewritten() throws {
        let inner = #"{"note": "CA, NY: $189,000"}"#
        XCTAssertEqual(try repairJSON("```json\n" + inner + "\n```"), inner)
    }

    /// The repairs still repair — this is not a regression of the feature.
    func testGenuinelyBrokenJSONIsStillFixed() throws {
        XCTAssertTrue(try parses(repairJSON(#"{"a": 1,}"#)), "trailing comma")
        XCTAssertTrue(try parses(repairJSON(#"{a: 1}"#)), "unquoted key")
        XCTAssertTrue(try parses(repairJSON(#"{'a': 'b'}"#)), "single quotes")
        XCTAssertTrue(try parses(repairJSON("Here you go:\n{\"a\": 1}\nHope that helps!")), "prose around it")
    }

    /// Something truly unparseable must still throw rather than return junk.
    func testHopelessInputStillThrows() {
        XCTAssertThrowsError(try repairJSON("I could not find a job posting on this page."))
    }
}
