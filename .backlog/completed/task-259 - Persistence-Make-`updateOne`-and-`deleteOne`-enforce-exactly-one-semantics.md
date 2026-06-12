---
id: TASK-259
title: 'Persistence: Make `updateOne` and `deleteOne` enforce exactly-one semantics'
status: Done
assignee: []
created_date: '2026-06-12 02:51'
updated_date: '2026-06-12 03:09'
labels:
  - audit
  - persistence
  - data-integrity
dependencies: []
references:
  - core/Services/BackgroundStore.swift
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
`BackgroundStore.updateOne` and `deleteOne` throw when no row matches, but if multiple rows match they mutate or delete all matches. With incomplete uniqueness constraints, a duplicate row can turn a targeted operation into a broad mutation.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 `updateOne` and `deleteOne` detect multiple matches and fail clearly or intentionally constrain the fetch to a single row with documented semantics.
- [ ] #2 Call sites that rely on ID/key uniqueness have tests covering missing, single, and duplicate-match cases.
- [ ] #3 Bulk mutation helpers remain separate and clearly named for multi-row operations.
<!-- AC:END -->
