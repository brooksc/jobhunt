---
id: TASK-439
title: 'Extension queue: Surface when offline captures are trimmed for storage quota'
status: Done
assignee: []
created_date: '2026-06-13 18:25'
updated_date: '2026-06-17 04:34'
labels:
  - audit
  - extension
  - queue
  - data-quality
dependencies: []
references:
  - extension/retry_queue.js
  - extension/status.js
  - extension/export_csv.js
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
`fitItemToQuota` silently truncates `visible_text` until the queued item fits under `MAX_ITEM_BYTES`, while preserving other fields. The queue item does not record that truncation happened, so users may later sync or export a lossy capture without knowing the job description was shortened.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Queued captures record whether `visible_text` was truncated and, where feasible, original vs stored character counts.
- [x] #2 The capture queue UI surfaces truncated captures clearly before sync/export.
- [x] #3 CSV export includes a truncation indicator or metadata column so exported rows are not mistaken for full captures.
- [x] #4 Sync behavior preserves the truncation marker or otherwise lets the app record that the source capture was partial.
- [x] #5 Add retry-queue/status/export tests for a capture trimmed to fit quota.
<!-- AC:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
`fitItemToQuota` now records truncation metadata on the queued payload — `visible_text_truncated`, `visible_text_original_chars`, `visible_text_stored_chars` (AC#1) — with the markers set before the byte-size binary search so they're accounted for and the trimmed item still fits MAX_ITEM_BYTES. status.js surfaces a "⚠ Description shortened to fit storage (stored/original chars)" line on truncated queue items (AC#2). export_csv.js adds `visible_text_truncated` + `visible_text_original_chars` columns (AC#3). The markers travel in the payload, so they're preserved through sync to the app (AC#4). Tests (node --test): fitItemToQuota sets the markers + the trimmed item still fits, omits them under quota; CSV exposes the truncation column and flags trimmed vs full rows; header-order test updated. Full extension suite (69) green. Note: I can't load the extension in a real browser here — verified via the JS test suite + review.
<!-- SECTION:FINAL_SUMMARY:END -->
