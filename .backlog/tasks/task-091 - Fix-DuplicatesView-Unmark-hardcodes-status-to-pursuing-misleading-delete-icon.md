---
id: TASK-091
title: >-
  Fix DuplicatesView: Unmark hardcodes status to pursuing, misleading delete
  icon
status: To Do
assignee: []
created_date: '2026-06-10 07:31'
labels:
  - bug
  - ui-audit
dependencies: []
priority: high
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
HIGH: `handleUnmark` hardcodes `job.status = .pursuing`, destroying any prior status (applied, passed, closed, etc.) silently. Fix: preserve original status — only clear `duplicateOfJobID` without overwriting status, or store and restore the prior status.

MEDIUM: `Discard this one` button uses `archivebox` SF Symbol (implies reversible archive) but performs hard delete. Fix: use `trash` icon or rename/rephrase. Confirmation alert already exists but the icon is misleading.

Files: `app/Views/Duplicates/DuplicatesView.swift`
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Unmark as Duplicate preserves the job's existing status
- [ ] #2 Discard button uses trash icon to accurately signal destructive action
<!-- AC:END -->
