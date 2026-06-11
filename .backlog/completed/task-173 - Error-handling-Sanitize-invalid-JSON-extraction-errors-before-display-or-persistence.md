---
id: TASK-173
title: >-
  Error handling: Sanitize invalid JSON extraction errors before display or
  persistence
status: Done
assignee: []
created_date: '2026-06-11 21:45'
updated_date: '2026-06-11 22:19'
labels:
  - audit
  - error-handling
  - llm
  - privacy
dependencies: []
references:
  - core/LLM/ExtractionEngine.swift
  - core/LLM/LLMProvider.swift
  - core/LLM/QueueActor.swift
priority: low
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
`ExtractionEngineError.invalidJSON` includes up to 200 characters of raw model output in `errorDescription`, while provider HTTP errors are explicitly sanitized. Decide whether model output should be shown only in debug logs or a redacted diagnostic field, then make persisted/user-visible extraction errors safe and consistent.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 User-visible and persisted invalid-JSON errors do not expose raw model output unless explicitly allowed by a debug setting.
- [ ] #2 Debug diagnostics retain enough context to troubleshoot malformed responses safely.
- [ ] #3 Tests cover the sanitized invalid-JSON localized description.
<!-- AC:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Changed `ExtractionEngineError.invalidJSON` `errorDescription` from exposing `json.prefix(200)` to a safe "LLM response could not be parsed as JSON" message. The associated String value is preserved for programmatic access/debug logging but no longer appears in user-visible or persisted error descriptions. Test added verifying raw output is not exposed.
<!-- SECTION:FINAL_SUMMARY:END -->
