---
id: TASK-196
title: 'Extension: Add timeout and fail-open behavior for Greenhouse enrichment'
status: To Do
assignee: []
created_date: '2026-06-11 23:47'
labels:
  - extension
  - capture
  - reliability
  - audit
dependencies: []
references:
  - extension/capture.js
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Greenhouse API enrichment runs during capture without an AbortSignal timeout. A stalled external request can block payload construction and prevent save or offline queue fallback.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Greenhouse enrichment uses a short timeout with AbortController or equivalent.
- [ ] #2 Timeout or API failure falls back to DOM-based capture without failing the whole capture.
- [ ] #3 Tests cover timeout/failure fallback behavior.
<!-- AC:END -->
