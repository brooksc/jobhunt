---
id: TASK-025
title: 'Deferred: evaluate query-builder UI only if current filters stop scaling'
status: Deferred
assignee: []
created_date: '2026-05-28 01:48'
updated_date: '2026-05-31 23:59'
labels: []
dependencies:
  - TASK-024
priority: low
ordinal: 23000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Current Node app status: a custom dynamic filter menu is implemented and fits the current Jobs workflow better than a general-purpose nested query builder. Do not vendor react-querybuilder by default.

Revive this only if users need nested boolean logic, complex reusable queries, or server-backed filtering that the current UI cannot represent.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Identify a real filtering use case that current dynamic filters cannot handle.
- [ ] #2 Evaluate whether a query builder improves that use case without making common filtering slower.
- [ ] #3 If adopted, prototype against Jobs first before replacing Sites filters.
- [ ] #4 If adopted, render fields from a shared field definition list rather than duplicating hardcoded field names.
- [ ] #5 If adopted, preserve existing saved views or provide a clear migration.
<!-- AC:END -->
