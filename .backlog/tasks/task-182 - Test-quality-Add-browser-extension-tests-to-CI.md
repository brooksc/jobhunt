---
id: TASK-182
title: 'Test quality: Add browser extension tests to CI'
status: Done
assignee: []
created_date: '2026-06-11 22:18'
updated_date: '2026-06-11 22:36'
labels:
  - audit
  - tests
  - ci
  - extension
dependencies: []
references:
  - extension/package.json
  - .github/workflows/swift-build.yml
  - extension/tests/test_retry_queue.js
  - extension/tests/test_export_csv.js
  - extension/tests/test_service_worker_contract.js
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
The extension has Node contract tests for retry queue, CSV export, and service worker behavior, but the CI fast gate only runs Swift CoreTests, ServerTests, and MCPTests. Add an extension test job or include `npm test --prefix extension` in CI so capture-queue and extension export regressions cannot merge unnoticed.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 CI runs the extension Node test suite on pull requests or the equivalent main build gate.
- [ ] #2 Extension test failures block the CI gate.
- [ ] #3 README/CONTRIBUTING test instructions mention how to run extension tests locally.
<!-- AC:END -->
