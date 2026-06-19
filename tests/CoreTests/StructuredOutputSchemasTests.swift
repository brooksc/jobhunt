import XCTest
@testable import JobhuntCore

/// TASK-461: the extraction/fit JSON Schemas sent as strict structured output must be valid JSON and
/// compatible with what the parsers (JobFieldNormalizer / FitScorer) read back.
final class StructuredOutputSchemasTests: XCTestCase {
    private func parse(_ kind: StructuredOutputKind) throws -> [String: Any] {
        let (_, schema) = StructuredOutputSchemas.schema(for: kind)
        let obj = try JSONSerialization.jsonObject(with: Data(schema.utf8))
        return try XCTUnwrap(obj as? [String: Any], "schema must be a JSON object")
    }

    // AC#1: both schemas parse as valid JSON.

    func testExtractionSchemaIsValidJSON() throws {
        let schema = try parse(.jobExtraction)
        XCTAssertEqual(schema["type"] as? String, "object")
        // OpenAI strict mode requires additionalProperties:false.
        XCTAssertEqual(schema["additionalProperties"] as? Bool, false)
        XCTAssertNotNil(schema["required"] as? [String])
    }

    func testFitSchemaIsValidJSON() throws {
        let schema = try parse(.fitScore)
        XCTAssertEqual(schema["type"] as? String, "object")
        XCTAssertEqual(schema["additionalProperties"] as? Bool, false)
        XCTAssertNotNil(schema["required"] as? [String])
    }

    // AC#3: shapes are compatible with the parsers.

    func testExtractionSchemaExposesFieldsTheNormalizerReads() throws {
        let props = try XCTUnwrap(parse(.jobExtraction)["properties"] as? [String: Any])
        // JobFieldNormalizer / projections read these snake_case keys.
        for key in [
            "company",
            "title",
            "location",
            "remote_type",
            "salary_min",
            "salary_max",
            "salary_currency",
            "salary_note",
            "employment_type",
            "seniority",
            "skills",
            "requirements",
            "nice_to_haves",
            "application_url"
        ] {
            XCTAssertNotNil(props[key], "extraction schema must expose '\(key)'")
        }
    }

    func testFitSchemaDimensionsMatchFitScorer() throws {
        let props = try XCTUnwrap(parse(.fitScore)["properties"] as? [String: Any])
        // FitScorer reads dimensions:[{name,score}]; the engine derives the not-met list from the
        // per-requirement assessments (TASK-490).
        let dimensions = try XCTUnwrap(props["dimensions"] as? [String: Any])
        XCTAssertEqual(dimensions["type"] as? String, "array")
        let item = try XCTUnwrap(dimensions["items"] as? [String: Any])
        let itemProps = try XCTUnwrap(item["properties"] as? [String: Any])
        XCTAssertNotNil(itemProps["name"], "dimension item must have a name")
        XCTAssertNotNil(itemProps["score"], "dimension item must have a score")

        // TASK-490: requirement_assessments replaces the free-form met/not-met arrays — one object
        // per job qualification with a met/partial/missing status, so gaps are consistent per resume.
        let assessments = try XCTUnwrap(props["requirement_assessments"] as? [String: Any])
        XCTAssertEqual(assessments["type"] as? String, "array")
        let aItem = try XCTUnwrap(assessments["items"] as? [String: Any])
        let aProps = try XCTUnwrap(aItem["properties"] as? [String: Any])
        XCTAssertNotNil(aProps["requirement"])
        XCTAssertNotNil(aProps["status"])
        XCTAssertNotNil(aProps["evidence"])
        let statusEnum = (aProps["status"] as? [String: Any])?["enum"] as? [String]
        XCTAssertEqual(Set(statusEnum ?? []), ["met", "partial", "missing"])
    }
}
