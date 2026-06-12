---
id: TASK-255
title: 'Domain correctness: Update stale status/domain specification docs'
status: To Do
assignee: []
created_date: '2026-06-12 02:43'
labels:
  - audit
  - domain
  - documentation
dependencies: []
references:
  - docs/job-detail-pane-spec.md
  - core/Models/Enums.swift
  - core/Services/JobService.swift
priority: low
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
`docs/job-detail-pane-spec.md` still references legacy statuses such as `saved` and `not_available`, while the current enum uses `new`, `closed`, and `expired`. The compare-tab spec says unmarking a duplicate sets status `.saved`, but current code only clears `duplicateOfJobID`.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Job status documentation matches the current `JobStatus` enum and intended workflow semantics.
- [ ] #2 Duplicate compare-tab documentation matches the implemented or newly corrected unmark behavior.
- [ ] #3 Docs distinguish persisted model state from UI labels where they differ.
<!-- AC:END -->
