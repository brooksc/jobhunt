---
id: TASK-133
title: 'Tests: Add active Chrome extension regression tests'
status: To Do
assignee: []
created_date: '2026-06-11 03:26'
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
