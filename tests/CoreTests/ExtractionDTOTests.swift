import XCTest
@testable import JobhuntCore

/// TASK-456: typed decode boundary for the LLM extraction schema.
final class ExtractionDTOTests: XCTestCase {
    private func parse(_ json: String) throws -> [String: Any] {
        let data = json.data(using: .utf8)!
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    // MARK: - Valid

    func testValidExtractionDecodes() throws {
        let raw = try parse("""
        {"title":"Staff Engineer","company":"Acme","location":"Remote","remote_type":"remote",
         "salary_min":120000,"salary_max":180000,"salary_currency":"USD","salary_note":"base",
         "salary_hourly_min":null,"salary_hourly_max":null,"employment_type":"full_time",
         "seniority":"staff","skills":["Swift","Go"],"summary":"Build things",
         "requirements":["5y"],"nice_to_haves":["k8s"],"benefits":["401k"],
         "application_url":"https://acme.com/apply","application_instructions":null}
        """)
        let dto = try ExtractionDTO(raw: raw)
        XCTAssertEqual(dto.title, "Staff Engineer")
        XCTAssertEqual(dto.salaryMin, 120000)
        XCTAssertEqual(dto.salaryMax, 180000)
        XCTAssertEqual(dto.skills, ["Swift", "Go"])
        XCTAssertEqual(dto.requirements, ["5y"])
        XCTAssertNil(dto.salaryHourlyMin)
        XCTAssertNil(dto.applicationInstructions)
    }

    // MARK: - Missing optional fields (text-mode providers omit keys)

    func testMissingOptionalFieldsBecomeNilAndEmptyArrays() throws {
        let raw = try parse(#"{"title":"Engineer"}"#)
        let dto = try ExtractionDTO(raw: raw)
        XCTAssertEqual(dto.title, "Engineer")
        XCTAssertNil(dto.company)
        XCTAssertNil(dto.salaryMin)
        XCTAssertEqual(dto.skills, [])
        XCTAssertEqual(dto.requirements, [])
        XCTAssertEqual(dto.benefits, [])
    }

    func testExplicitNullsBecomeNil() throws {
        let raw = try parse(#"{"title":null,"salary_min":null,"skills":null}"#)
        let dto = try ExtractionDTO(raw: raw)
        XCTAssertNil(dto.title)
        XCTAssertNil(dto.salaryMin)
        XCTAssertEqual(dto.skills, [])
    }

    // MARK: - Supported coercions (AC#3)

    func testNumericStringSalaryCoercesToInt() throws {
        let raw = try parse(#"{"salary_min":"120000","salary_max":"180000"}"#)
        let dto = try ExtractionDTO(raw: raw)
        XCTAssertEqual(dto.salaryMin, 120000)
        XCTAssertEqual(dto.salaryMax, 180000)
    }

    func testFloatSalaryRoundsToInt() throws {
        let raw = try parse(#"{"salary_min":120000.0,"salary_max":180499.6}"#)
        let dto = try ExtractionDTO(raw: raw)
        XCTAssertEqual(dto.salaryMin, 120000)
        XCTAssertEqual(dto.salaryMax, 180500)
    }

    func testHourlyAcceptsNumberAndNumericString() throws {
        let raw = try parse(#"{"salary_hourly_min":55,"salary_hourly_max":"72.5"}"#)
        let dto = try ExtractionDTO(raw: raw)
        XCTAssertEqual(dto.salaryHourlyMin, 55)
        XCTAssertEqual(dto.salaryHourlyMax, 72.5)
    }

    func testArrayDropsNonStringElements() throws {
        let raw = try parse(#"{"skills":["Swift",123,null,"Go"]}"#)
        let dto = try ExtractionDTO(raw: raw)
        XCTAssertEqual(dto.skills, ["Swift", "Go"])
    }

    // MARK: - Malformed shapes throw (AC#2)

    func testStringFieldGivenObjectThrows() throws {
        let raw = try parse(#"{"title":{"nested":"x"}}"#)
        XCTAssertThrowsError(try ExtractionDTO(raw: raw)) {
            guard case ExtractionEngineError.malformedField(let field, _) = $0 else {
                return XCTFail("expected malformedField, got \($0)")
            }
            XCTAssertEqual(field, "title")
        }
    }

    func testNonNumericStringSalaryThrows() throws {
        let raw = try parse(#"{"salary_min":"competitive"}"#)
        XCTAssertThrowsError(try ExtractionDTO(raw: raw)) {
            guard case ExtractionEngineError.malformedField(let field, _) = $0 else {
                return XCTFail("expected malformedField, got \($0)")
            }
            XCTAssertEqual(field, "salary_min")
        }
    }

    func testArrayFieldGivenStringThrows() throws {
        let raw = try parse(#"{"skills":"Swift, Go"}"#)
        XCTAssertThrowsError(try ExtractionDTO(raw: raw)) {
            guard case ExtractionEngineError.malformedField(let field, _) = $0 else {
                return XCTFail("expected malformedField, got \($0)")
            }
            XCTAssertEqual(field, "skills")
        }
    }

    func testBooleanSalaryThrows() throws {
        let raw = try parse(#"{"salary_min":true}"#)
        XCTAssertThrowsError(try ExtractionDTO(raw: raw)) {
            guard case ExtractionEngineError.malformedField = $0 else {
                return XCTFail("expected malformedField, got \($0)")
            }
        }
    }

    // MARK: - Round-trip preserves normalization keys

    func testAsDictUsesSnakeCaseKeys() throws {
        let raw = try parse(#"{"remote_type":"hybrid","salary_min":100000,"nice_to_haves":["x"]}"#)
        let dict = try ExtractionDTO(raw: raw).asDict()
        XCTAssertEqual(dict["remote_type"] as? String, "hybrid")
        XCTAssertEqual(dict["salary_min"] as? Int, 100000)
        XCTAssertEqual(dict["nice_to_haves"] as? [String], ["x"])
    }
}
