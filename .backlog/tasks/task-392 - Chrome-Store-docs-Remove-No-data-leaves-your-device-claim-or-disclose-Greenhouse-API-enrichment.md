---
id: TASK-392
title: >-
  Chrome Store docs: Remove 'No data leaves your device' claim or disclose
  Greenhouse API enrichment
status: To Do
assignee: []
created_date: '2026-06-12 23:02'
labels:
  - audit
  - docs
  - privacy
  - chrome-extension
  - release
dependencies: []
references:
  - chromestore/store-listing.md
  - chromestore/PRIVACY.md
  - extension/capture.js
  - docs/chrome-web-store-review.md
priority: high
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
The Chrome Store listing suggested privacy copy says no data leaves the device, but Greenhouse captures make a direct browser request to the public Greenhouse boards API. The extension privacy policy already discloses this; align the store listing and review notes so submission copy does not contradict extension behavior.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Chrome Store listing privacy copy accurately discloses Greenhouse public API enrichment for Greenhouse pages.
- [ ] #2 Review notes and listing copy no longer make an absolute 'no data leaves your device' claim unless scoped to non-Greenhouse captures.
- [ ] #3 The disclosure remains clear that captured data is otherwise sent to the local companion app over localhost.
- [ ] #4 Submission checklist includes verifying listing/privacy consistency before upload.
<!-- AC:END -->
