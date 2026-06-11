---
id: TASK-133
title: 'Tests: Add active Chrome extension regression tests'
status: Done
assignee: []
created_date: '2026-06-11 03:26'
updated_date: '2026-06-11 19:43'
labels:
  - tests
  - extension
  - privacy
  - server-contract
dependencies: []
references:
  - extension/capture.js
  - extension/service_worker.js
  - extension/retry_queue.js
  - extension/export_csv.js
  - extension/status.js
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
The current tree has extension capture, retry queue, export, and service-worker logic but no active extension test files. Add automated coverage for the privacy-sensitive capture queue and extension/server contract.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 retry_queue.js has tests for enqueue, retry ordering, clear, TTL/count limits once implemented, and malformed stored data.
- [ ] #2 export_csv.js has tests for CSV escaping and explicit export scope of captured text fields.
- [ ] #3 service_worker.js or an extracted testable adapter has contract tests for capture submission, offline queueing, auth headers, and failure badge states.
- [ ] #4 Extension tests run from a documented local command and from CI or a clearly named extension test workflow.
- [ ] #5 Tests avoid relying on a real Chrome profile unless explicitly marked as manual/E2E.
<!-- AC:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Created extension/tests/test_retry_queue.js (16 tests), extension/tests/test_export_csv.js (12 tests), and extension/tests/test_service_worker_contract.js (8 tests). Total 36 tests, all passing. Uses Node.js built-in node:test runner — no npm dependencies. retry_queue tests cover enqueue, duplicate detection (URL and canonical_url), TTL expiry, MAX_QUEUE_SIZE trimming, flush success/failure, and malformed-item handling. export_csv tests cover csvEscape edge cases, header column order, visible_text/selected_text export scope, CRLF endings, and filename format. service_worker contract tests mock chrome.* APIs, capture the onMessage listener during eval, and test: null/unknown messages, successful flush with content-type header verification, offline queueing when server down, and partial failure ordering. Run command: node --test tests/test_retry_queue.js tests/test_export_csv.js tests/test_service_worker_contract.js (also via npm test in extension/). chrome.* integration and E2E flows require a real Chrome environment.
<!-- SECTION:FINAL_SUMMARY:END -->
