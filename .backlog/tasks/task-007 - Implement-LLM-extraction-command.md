---
id: TASK-007
title: Implement LLM extraction command
status: Done
assignee: []
created_date: '2026-05-27 04:35'
updated_date: '2026-05-27 05:09'
labels:
  - m3-extraction
  - llm
  - server
dependencies:
  - TASK-003
modified_files:
  - pyproject.toml
  - uv.lock
  - src/jobhunt/cli.py
  - src/jobhunt/db.py
  - src/jobhunt/extract.py
  - src/jobhunt/models.py
  - tests/test_extract.py
  - .gitignore
priority: high
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Add the first extraction workflow that reads pending captures from SQLite and creates structured job fields using an LLM. Raw captures remain the source of truth but extraction should use the stored cleaned job description as its primary input. Extraction must be rerunnable later as schemas prompts or cleaning improve. The initial LLM provider is LM Studio at http://192.168.7.230:1234 using model google/gemma-4-e4b via an OpenAI-compatible API.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 `uv run jobhunt extract` processes pending captures from SQLite
- [x] #2 The extraction prompt requires strict JSON matching the extracted job schema in spec.md
- [x] #3 Validated extraction results update the related job record and set extraction_status appropriately
- [x] #4 Missing source fields are represented as null or empty lists rather than guessed values
- [x] #5 Failed extractions preserve an error state that can be retried
- [x] #6 Focused tests cover schema validation and extraction persistence using a mocked LLM response
- [x] #7 Extraction uses cleaned_description as the primary job description input while retaining traceability to raw capture text
- [x] #8 If cleaned_description is missing extraction falls back to the best available raw text without deleting the capture
- [x] #9 The extraction command defaults to or supports configuring LM Studio base URL http://192.168.7.230:1234 and model google/gemma-4-e4b
- [x] #10 The LLM base URL and model can be overridden through CLI options or environment variables without code changes
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
Implement extraction as a small pipeline: query pending jobs/captures, choose cleaned_description with raw-text fallback, call LM Studio through an OpenAI-compatible HTTP client, validate JSON with Pydantic, persist extracted fields or failure state, expose `uv run jobhunt extract` with configurable base URL/model, and cover persistence with mocked LLM tests.
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Implemented extraction against an OpenAI-compatible LM Studio endpoint with defaults for http://192.168.7.230:1234 and google/gemma-4-e4b. The CLI supports overriding base URL model and timeout. Automated tests use mocked extractor responses and cover success failure parsing and cleaned-description fallback. A live run against the current captured NVIDIA job timed out because LM Studio was not reachable from this machine; the job was marked failed with extraction_error 'timed out' and remains retryable.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Implemented the M3 extraction command. `uv run jobhunt extract` now reads pending or failed jobs, uses cleaned_description as the primary prompt input with raw text fallback, calls an OpenAI-compatible LM Studio client, validates strict JSON into an ExtractedJob model, and persists either extracted fields or a retryable failure state. Tests cover JSON parsing, successful mocked extraction persistence, failed extraction persistence, and fallback input selection.
<!-- SECTION:FINAL_SUMMARY:END -->
