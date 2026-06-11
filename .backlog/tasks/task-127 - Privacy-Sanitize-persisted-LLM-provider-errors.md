---
id: TASK-127
title: 'Privacy: Sanitize persisted LLM provider errors'
status: To Do
assignee: []
created_date: '2026-06-11 03:01'
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
