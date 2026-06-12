---
id: TASK-326
title: >-
  OpenAI-compatible transport: Narrow response-format fallback to supported
  errors
status: Done
assignee: []
created_date: '2026-06-12 20:02'
updated_date: '2026-06-12 20:18'
labels:
  - audit
  - llm-provider
  - errors
dependencies: []
references:
  - core/LLM/Providers/OpenAICompatibleTransport.swift
  - tests/CoreTests/LLMProviderTests.swift
priority: low
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
OpenAICompatibleTransport treats any HTTP 400 as a response_format negotiation failure and retries lower formats. That is correct for unsupported response_format, but it retries unrelated bad-request failures and can obscure the real first error.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Transport only falls back on 400 responses that indicate unsupported response_format/json_schema behavior, or records the original 400 clearly.
- [ ] #2 Unrelated 400 errors fail without unnecessary retries.
- [ ] #3 Tests cover unsupported response_format fallback and unrelated 400 behavior.
<!-- AC:END -->
