---
id: TASK-024
title: 'Deferred: backend saved views and server-side query filtering'
status: Deferred
assignee: []
created_date: '2026-05-28 01:48'
updated_date: '2026-05-31 23:59'
labels: []
dependencies: []
priority: low
ordinal: 22000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Current Node app status: saved views and dynamic filters are implemented client-side with localStorage and are working for the current dataset size. This card is deferred until there is a concrete need for cross-browser saved views, synced settings, or server-side filtering for larger datasets.

If revived, implement a backend saved-view/filter API with allowlisted SQL generation. Do not duplicate the current working client-side filter stack unless there is a product reason.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Confirm client-side filtering is no longer sufficient (dataset size, sync requirement, or saved-view portability).
- [ ] #2 If backend persistence is needed, add a SQLite saved_views table with page, name, rule JSON, and timestamps.
- [ ] #3 Add GET/POST/DELETE saved-view endpoints and migrate or import existing localStorage views.
- [ ] #4 If server-side filtering is needed, define an allowlisted field schema before accepting any rule tree from the browser.
- [ ] #5 SQL generation uses parameterized values and never interpolates unvalidated user-supplied field names.
- [ ] #6 Existing client-side filters continue to work or are intentionally replaced with a tested migration path.
<!-- AC:END -->
