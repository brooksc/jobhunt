---
id: TASK-128
title: 'Security: Document or avoid Google provider API key in URL query'
status: To Do
assignee: []
created_date: '2026-06-11 03:01'
labels:
  - security
  - llm
  - google-provider
dependencies: []
references:
  - core/LLM/Providers/GoogleProvider.swift
  - tests/CoreTests/LLMProviderTests.swift
priority: low
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
GoogleProvider builds requests with the API key in the URL query string. If the API supports a header-based credential path, prefer that; otherwise document the exception and ensure URLs are not logged or persisted.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 GoogleProvider uses a header-based API key transport if supported by the target API.
- [ ] #2 If query-string API keys are required, the reason is documented near the provider implementation.
- [ ] #3 Provider logging and errors never persist or print URLs containing API keys.
- [ ] #4 Tests or code review checks verify Google request failures redact credentials.
<!-- AC:END -->
