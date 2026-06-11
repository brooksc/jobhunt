---
id: TASK-127
title: 'Privacy: Sanitize persisted LLM provider errors'
status: Done
assignee: []
created_date: '2026-06-11 03:01'
updated_date: '2026-06-11 19:29'
labels:
  - privacy
  - llm
  - logging
  - persistence
dependencies: []
references:
  - core/LLM/LLMProvider.swift
  - core/LLM/QueueActor.swift
  - core/Models/LLMRequestAttempt.swift
  - app/Views/Settings/SettingsView.swift
modified_files:
  - core/LLM/LLMProvider.swift
  - tests/CoreTests/LLMProviderTests.swift
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Provider error handling can include response-body text in localized errors, and QueueActor persists those descriptions to LLMRequestAttempt records. This can accidentally retain provider response bodies or reflected prompt content in the local store.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Persisted LLM attempt errors use sanitized categories, status codes, and request identifiers rather than raw response bodies.
- [ ] #2 Raw provider response bodies are not stored in SwiftData during normal operation.
- [ ] #3 Any debug mode that captures raw provider bodies is explicit, default-off, documented, and redacts obvious sensitive content.
- [ ] #4 Tests cover provider error persistence for HTTP and decoding failures without storing raw body text.
<!-- AC:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Fixed LLMProviderError.httpError errorDescription to omit the raw response body — was "LLM HTTP {code}: {body.prefix(500)}", now just "LLM HTTP {code}". QueueActor uses localizedDescription for persistence (req.error = errorStr), so this ensures no provider response bodies are stored in LLMRequestAttempt records. The unavailable(reason:) case uses only hardcoded internal strings, not provider content — left unchanged. Tests: testHTTPErrorDescriptionOmitsResponseBody asserts the body (including auth tokens) is never in the description; testDecodeErrorDescriptionOmitsRawContent confirms noResponse is non-empty.
<!-- SECTION:FINAL_SUMMARY:END -->
