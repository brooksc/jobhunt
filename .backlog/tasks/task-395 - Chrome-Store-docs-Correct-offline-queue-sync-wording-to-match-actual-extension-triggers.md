---
id: TASK-395
title: >-
  Chrome Store docs: Correct offline queue sync wording to match actual
  extension triggers
status: Done
assignee: []
created_date: '2026-06-12 23:02'
updated_date: '2026-06-15 18:40'
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
modified_files:
  - chromestore/store-listing.md
  - docs/chrome-web-store-review.md
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
The store listing says queued captures sync automatically the next time the app starts, but the service worker flushes the queue before a new capture or when the user explicitly syncs from the queue/menu. Update listing and review instructions to avoid promising app-start automatic sync unless that behavior is implemented.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Chrome Store listing describes current queue sync triggers accurately.
- [x] #2 Review instructions test the actual supported sync flow.
- [ ] #3 If automatic app-start sync remains advertised, extension/app code implements and tests that behavior.
- [x] #4 User-facing queue text and store copy agree on when queued captures flush.
<!-- AC:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
store-listing.md no longer claims queued captures "sync automatically the next time the app starts" — the service worker flushes the queue before a new capture (when the app is reachable) or on demand, so the copy now reads "synced automatically the next time you capture a job while the app is reachable — or on demand via Open capture queue → Sync to Jobhunt" (AC#1/#4). The chrome-web-store-review.md reviewer steps already exercise the real manual "Sync to Jobhunt from the capture queue" flow (AC#2). AC#3 N/A — automatic app-start sync is no longer advertised, so no new code/tests needed.
<!-- SECTION:FINAL_SUMMARY:END -->
