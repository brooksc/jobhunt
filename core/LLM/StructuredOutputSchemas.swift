import Foundation

/// JSON Schemas for providers that support strict structured output via a JSON Schema
/// (Anthropic `output_config.format`, OpenAI-compatible `response_format.json_schema`).
///
/// They use the snake_case keys that `ExtractionEngine` reads back and stay within Anthropic's
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
        "application_instructions": {"type": ["string", "null"]},
        "confidence": {"type": ["number", "null"]}
      },
      "required": [
        "company", "title", "location", "remote_type", "salary_min", "salary_max",
        "salary_hourly_min", "salary_hourly_max", "salary_currency", "salary_note",
        "employment_type", "seniority", "skills", "summary", "requirements",
        "nice_to_haves", "benefits", "application_url", "application_instructions", "confidence"
      ]
    }
    """

    static let fitScore = """
    {
      "type": "object",
      "additionalProperties": false,
      "properties": {
        "summary": {"type": ["string", "null"]},
        "requirement_assessments": {
          "type": "array",
          "items": {
            "type": "object",
            "additionalProperties": false,
            "properties": {
              "requirement": {"type": "string"},
              "kind": {"type": "string", "enum": ["required", "preferred"]},
              "status": {"type": "string", "enum": ["met", "partial", "missing"]},
              "evidence": {"type": "string"}
            },
            "required": ["requirement", "kind", "status", "evidence"]
          }
        },
        "dimensions": {
          "type": "array",
          "items": {
            "type": "object",
            "additionalProperties": false,
            "properties": {
              "name": {"type": "string"},
              "score": {"type": "integer"},
              "rationale": {"type": "string"}
            },
            "required": ["name", "score", "rationale"]
          }
        }
      },
      "required": ["summary", "requirement_assessments", "dimensions"]
    }
    """
}
