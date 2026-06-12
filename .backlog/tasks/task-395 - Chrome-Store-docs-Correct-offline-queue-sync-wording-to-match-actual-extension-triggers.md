---
id: TASK-395
title: >-
  Chrome Store docs: Correct offline queue sync wording to match actual
  extension triggers
status: To Do
assignee: []
created_date: '2026-06-12 23:02'
labels:
  - audit
  - docs
  - chrome-extension
  - release
dependencies: []
references:
  - chromestore/store-listing.md
  - extension/service_worker.js
  - extension/status.js
  - docs/chrome-web-store-review.md
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
The store listing says queued captures sync automatically the next time the app starts, but the service worker flushes the queue before a new capture or when the user explicitly syncs from the queue/menu. Update listing and review instructions to avoid promising app-start automatic sync unless that behavior is implemented.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Chrome Store listing describes current queue sync triggers accurately.
- [ ] #2 Review instructions test the actual supported sync flow.
- [ ] #3 If automatic app-start sync remains advertised, extension/app code implements and tests that behavior.
- [ ] #4 User-facing queue text and store copy agree on when queued captures flush.
<!-- AC:END -->
