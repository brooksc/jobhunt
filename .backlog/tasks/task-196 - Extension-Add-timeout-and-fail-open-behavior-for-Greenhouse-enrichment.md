---
id: TASK-196
title: 'Extension: Add timeout and fail-open behavior for Greenhouse enrichment'
status: Done
assignee: []
created_date: '2026-06-11 23:47'
updated_date: '2026-06-12 00:00'
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
- [x] #1 Greenhouse enrichment uses a short timeout with AbortController or equivalent.
- [x] #2 Timeout or API failure falls back to DOM-based capture without failing the whole capture.
- [x] #3 Tests cover timeout/failure fallback behavior.
<!-- AC:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Added `GREENHOUSE_TIMEOUT_MS = 5000` constant and `AbortController` to `fetchGreenhouseJobData` in capture.js. The timer calls `controller.abort()` after 5 seconds; `signal` is passed to `fetch`. Both success and catch paths call `clearTimeout`. Abort errors and all API failures return `null`, so capture falls back to DOM-based extraction. Added `test_greenhouse_timeout.js` with 7 source-analysis tests. All 59 extension tests pass.
<!-- SECTION:FINAL_SUMMARY:END -->
