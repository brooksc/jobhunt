import Foundation

// MARK: - ExtractionDTO (TASK-456)

/// Typed decode boundary for the LLM job-extraction JSON. The provider response (already repaired
/// and parsed into `[String: Any]`) is validated into this DTO *before* normalization and
/// persistence, so provider drift surfaces as a clear invalid-response error instead of silently
/// dropping fields. Mirrors `StructuredOutputSchemas.jobExtraction`: every scalar is nullable, the
/// four list fields are arrays of strings.
///
/// Coercion is deliberate and narrow (text-mode providers don't honor the JSON-Schema types):
/// - integer fields accept an integral number or a numeric string;
/// - number fields accept any number or a numeric string;
/// - array fields tolerate a missing/null value (→ empty) and skip non-string elements.
/// A present-but-incompatible shape (e.g. a string field given an object, or a non-numeric string
/// for a salary) throws `ExtractionEngineError.malformedField`.
public struct ExtractionDTO {
    public var company: String?
    public var title: String?
    public var location: String?
    public var remoteType: String?
    public var salaryMin: Int?
    public var salaryMax: Int?
    public var salaryHourlyMin: Double?
    public var salaryHourlyMax: Double?
    public var salaryCurrency: String?
    public var salaryNote: String?
    public var employmentType: String?
    public var seniority: String?
    public var skills: [String]
    public var summary: String?
    public var requirements: [String]
    public var niceToHaves: [String]
    public var benefits: [String]
    public var applicationURL: String?
    public var applicationInstructions: String?

    public init(raw: [String: Any]) throws {
        company = try Self.string(raw, "company")
        title = try Self.string(raw, "title")
        location = try Self.string(raw, "location")
        remoteType = try Self.string(raw, "remote_type")
        salaryMin = try Self.int(raw, "salary_min")
        salaryMax = try Self.int(raw, "salary_max")
        salaryHourlyMin = try Self.double(raw, "salary_hourly_min")
        salaryHourlyMax = try Self.double(raw, "salary_hourly_max")
        salaryCurrency = try Self.string(raw, "salary_currency")
        salaryNote = try Self.string(raw, "salary_note")
        employmentType = try Self.string(raw, "employment_type")
        seniority = try Self.string(raw, "seniority")
        skills = try Self.stringArray(raw, "skills")
        summary = try Self.string(raw, "summary")
        requirements = try Self.stringArray(raw, "requirements")
        niceToHaves = try Self.stringArray(raw, "nice_to_haves")
        benefits = try Self.stringArray(raw, "benefits")
        applicationURL = try Self.string(raw, "application_url")
        applicationInstructions = try Self.string(raw, "application_instructions")
    }

    /// Rebuild the snake_case dict the normalization pipeline + `ExtractionResult` read from.
    /// `confidence` is not part of the strict schema; the caller re-injects it from the raw payload.
    public func asDict() -> [String: Any?] {
        [
            "company": company,
            "title": title,
            "location": location,
            "remote_type": remoteType,
            "salary_min": salaryMin,
            "salary_max": salaryMax,
            "salary_hourly_min": salaryHourlyMin,
            "salary_hourly_max": salaryHourlyMax,
            "salary_currency": salaryCurrency,
            "salary_note": salaryNote,
            "employment_type": employmentType,
            "seniority": seniority,
            "skills": skills,
            "summary": summary,
            "requirements": requirements,
            "nice_to_haves": niceToHaves,
            "benefits": benefits,
            "application_url": applicationURL,
            "application_instructions": applicationInstructions
        ]
    }

    // MARK: - Coercion helpers

    /// True only for a JSON `null` (bridged to NSNull). A missing key is also treated as null.
    private static func isNull(_ value: Any?) -> Bool {
        value == nil || value is NSNull
    }

    /// NSNumber from JSON bridges booleans into the numeric space (`true as? Int == 1`); guard so a
    /// stray boolean isn't silently coerced to 0/1 in a numeric field.
    private static func isBool(_ value: Any) -> Bool {
        (value as? NSNumber).map { CFGetTypeID($0) == CFBooleanGetTypeID() } ?? false
    }

    private static func string(_ raw: [String: Any], _ key: String) throws -> String? {
        let value = raw[key]
        if isNull(value) { return nil }
        guard let str = value as? String else {
            throw ExtractionEngineError.malformedField(field: key, reason: "expected string")
        }
        return str
    }

    private static func int(_ raw: [String: Any], _ key: String) throws -> Int? {
        let value = raw[key]
        if isNull(value) { return nil }
        guard let value else { return nil }
        if isBool(value) { throw ExtractionEngineError.malformedField(field: key, reason: "expected integer") }
        if let num = value as? NSNumber { return Int(num.doubleValue.rounded()) }
        if let str = value as? String {
            let trimmed = str.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { return nil }
            if let parsed = Double(trimmed), parsed.isFinite { return Int(parsed.rounded()) }
        }
        throw ExtractionEngineError.malformedField(field: key, reason: "expected integer")
    }

    private static func double(_ raw: [String: Any], _ key: String) throws -> Double? {
        let value = raw[key]
        if isNull(value) { return nil }
        guard let value else { return nil }
        if isBool(value) { throw ExtractionEngineError.malformedField(field: key, reason: "expected number") }
        if let num = value as? NSNumber { return num.doubleValue }
        if let str = value as? String {
            let trimmed = str.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { return nil }
            if let parsed = Double(trimmed), parsed.isFinite { return parsed }
        }
        throw ExtractionEngineError.malformedField(field: key, reason: "expected number")
    }

    private static func stringArray(_ raw: [String: Any], _ key: String) throws -> [String] {
        let value = raw[key]
        if isNull(value) { return [] }
        guard let arr = value as? [Any] else {
            throw ExtractionEngineError.malformedField(field: key, reason: "expected array of strings")
        }
        return arr.compactMap { $0 as? String }
    }
}
