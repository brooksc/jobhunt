---
id: TASK-392
title: >-
  Chrome Store docs: Remove 'No data leaves your device' claim or disclose
  Greenhouse API enrichment
status: Done
assignee: []
created_date: '2026-06-12 23:02'
updated_date: '2026-06-15 04:10'
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
modified_files:
  - chromestore/store-listing.md
  - docs/chrome-web-store-review.md
priority: high
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
The Chrome Store listing suggested privacy copy says no data leaves the device, but Greenhouse captures make a direct browser request to the public Greenhouse boards API. The extension privacy policy already discloses this; align the store listing and review notes so submission copy does not contradict extension behavior.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Chrome Store listing privacy copy accurately discloses Greenhouse public API enrichment for Greenhouse pages.
- [x] #2 Review notes and listing copy no longer make an absolute 'no data leaves your device' claim unless scoped to non-Greenhouse captures.
- [x] #3 The disclosure remains clear that captured data is otherwise sent to the local companion app over localhost.
- [x] #4 Submission checklist includes verifying listing/privacy consistency before upload.
<!-- AC:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Replaced the unscoped "No data leaves your device" claim in chromestore/store-listing.md with copy that discloses the Greenhouse public-API enrichment (direct request to boards-api.greenhouse.io for Greenhouse pages, sending only a board id + job id, no credentials/personal data; no other external servers), scoped so localhost-only remains accurate otherwise — consistent with chromestore/PRIVACY.md which already discloses it. Added the Greenhouse disclosure bullet to docs/chrome-web-store-review.md "Required Disclosure" and a "Before each submission" checklist item to verify store-listing/PRIVACY consistency (no unscoped no-data-leaves claim) before upload.
<!-- SECTION:FINAL_SUMMARY:END -->
