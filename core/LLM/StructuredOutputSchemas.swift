import Foundation

/// JSON Schemas for providers that support strict structured output via a JSON Schema
/// (Anthropic `output_config.format`, OpenAI-compatible `response_format.json_schema`).
///
/// These mirror the Apple FoundationModels `@Generable` shapes in `FoundationModelsSchemas.swift`
/// and the snake_case keys that `ExtractionEngine` reads back. They stay within Anthropic's
/// structured-output limits: every object sets `additionalProperties: false`, nullable scalars use
/// `["<type>", "null"]`, and no unsupported constraints (`minLength`, `minimum`, regex) are used.
public enum StructuredOutputSchemas {
    /// Returns the `(name, schema)` pair for a structured-output kind, or nil if none applies.
    public static func schema(for kind: StructuredOutputKind) -> (name: String, schema: String) {
        switch kind {
        case .jobExtraction: ("job_extraction", jobExtraction)
        case .fitScore: ("fit_score", fitScore)
        }
    }

    static let jobExtraction = """
    {
      "type": "object",
      "additionalProperties": false,
      "properties": {
        "company": {"type": ["string", "null"]},
        "title": {"type": ["string", "null"]},
        "location": {"type": ["string", "null"]},
        "remote_type": {"type": ["string", "null"]},
        "salary_min": {"type": ["integer", "null"]},
        "salary_max": {"type": ["integer", "null"]},
        "salary_hourly_min": {"type": ["number", "null"]},
        "salary_hourly_max": {"type": ["number", "null"]},
        "salary_currency": {"type": ["string", "null"]},
        "salary_note": {"type": ["string", "null"]},
        "employment_type": {"type": ["string", "null"]},
        "seniority": {"type": ["string", "null"]},
        "skills": {"type": "array", "items": {"type": "string"}},
        "summary": {"type": ["string", "null"]},
        "requirements": {"type": "array", "items": {"type": "string"}},
        "nice_to_haves": {"type": "array", "items": {"type": "string"}},
        "benefits": {"type": "array", "items": {"type": "string"}},
        "application_url": {"type": ["string", "null"]},
        "application_instructions": {"type": ["string", "null"]}
      },
      "required": [
        "company", "title", "location", "remote_type", "salary_min", "salary_max",
        "salary_hourly_min", "salary_hourly_max", "salary_currency", "salary_note",
        "employment_type", "seniority", "skills", "summary", "requirements",
        "nice_to_haves", "benefits", "application_url", "application_instructions"
      ]
    }
    """

    static let fitScore = """
    {
      "type": "object",
      "additionalProperties": false,
      "properties": {
        "overall": {"type": "integer"},
        "summary": {"type": ["string", "null"]},
        "requirements_met": {"type": "array", "items": {"type": "string"}},
        "requirements_not_met": {"type": "array", "items": {"type": "string"}},
        "dimensions": {
          "type": "array",
          "items": {
            "type": "object",
            "additionalProperties": false,
            "properties": {
              "name": {"type": "string"},
              "score": {"type": "integer"},
              "weight": {"type": "number"},
              "rationale": {"type": "string"}
            },
            "required": ["name", "score", "weight", "rationale"]
          }
        }
      },
      "required": ["overall", "summary", "requirements_met", "requirements_not_met", "dimensions"]
    }
    """
}
