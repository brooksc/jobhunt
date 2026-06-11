---
id: TASK-173
title: >-
  Error handling: Sanitize invalid JSON extraction errors before display or
  persistence
status: To Do
assignee: []
created_date: '2026-06-11 21:45'
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
