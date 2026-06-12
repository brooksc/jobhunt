---
id: TASK-312
title: 'Migrator: Update stale uniqueness comments'
status: To Do
assignee: []
created_date: '2026-06-12 19:35'
labels:
  - audit
  - migration
  - docs
dependencies: []
references:
  - tools/migrator/Migration.swift
  - core/Models/Capture.swift
priority: low
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
The migrator comments still say Capture.rawHash has no @Attribute(.unique) DB constraint, but the model now marks rawHash unique. This is misleading in the data repair path.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Migrator comments accurately describe current model uniqueness constraints and rerun behavior.
- [ ] #2 Any remaining non-unique identity assumptions are documented precisely.
- [ ] #3 No behavior change is required unless the audit finds stale comments hiding real migration risk.
<!-- AC:END -->
