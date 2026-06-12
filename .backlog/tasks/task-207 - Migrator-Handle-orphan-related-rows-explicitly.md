---
id: TASK-207
title: 'Migrator: Handle orphan related rows explicitly'
status: Done
assignee: []
created_date: '2026-06-12 00:37'
updated_date: '2026-06-12 02:16'
labels:
  - migration
  - persistence
  - data-integrity
  - audit
dependencies: []
references:
  - tools/migrator/Migration.swift
  - tools/migrator/Verify.swift
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
The legacy migrator assigns optional parent relationships from lookup maps for actions, fit scores, LLM requests, contacts, and cover letters. Missing parent jobs can produce orphan rows that are invisible in normal workflows and not cleaned up by job cascades.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Migration policy for orphan related rows is documented: fail, skip, or import with explicit orphan status.
- [ ] #2 Migration summary reports skipped or orphaned rows by table.
- [ ] #3 Tests cover at least one missing-parent row for each chosen policy.
<!-- AC:END -->
