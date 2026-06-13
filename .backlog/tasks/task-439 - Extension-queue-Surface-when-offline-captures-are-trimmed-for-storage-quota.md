---
id: TASK-439
title: 'Extension queue: Surface when offline captures are trimmed for storage quota'
status: To Do
assignee: []
created_date: '2026-06-13 18:25'
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
- [ ] #1 Queued captures record whether `visible_text` was truncated and, where feasible, original vs stored character counts.
- [ ] #2 The capture queue UI surfaces truncated captures clearly before sync/export.
- [ ] #3 CSV export includes a truncation indicator or metadata column so exported rows are not mistaken for full captures.
- [ ] #4 Sync behavior preserves the truncation marker or otherwise lets the app record that the source capture was partial.
- [ ] #5 Add retry-queue/status/export tests for a capture trimmed to fit quota.
<!-- AC:END -->
