---
id: TASK-323
title: 'Google provider: Respect requested response format'
status: To Do
assignee: []
created_date: '2026-06-12 20:02'
labels:
  - audit
  - llm-provider
  - google
dependencies: []
references:
  - core/LLM/Providers/GoogleProvider.swift
  - app/Views/Settings/SettingsView.swift
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
GoogleProvider always sets generationConfig.responseMimeType to application/json even when ChatRequest.responseFormat is nil or text. This can break simple connection tests or future non-JSON prompts.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 GoogleProvider maps ChatRequest.responseFormat to Google generationConfig appropriately.
- [ ] #2 Text/no-format requests do not force JSON mode.
- [ ] #3 Provider tests cover JSON and plain text request paths.
<!-- AC:END -->
