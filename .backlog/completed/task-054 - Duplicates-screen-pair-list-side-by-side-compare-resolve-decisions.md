---
id: TASK-054
title: 'Duplicates screen: pair list, side-by-side compare, resolve decisions'
status: Done
assignee: []
created_date: '2026-06-07 22:49'
updated_date: '2026-06-08 03:31'
labels:
  - swift-rewrite
  - ui
  - screen
milestone: m-1
dependencies:
  - TASK-045
  - TASK-046
  - TASK-038
documentation:
  - swift-plan.md
  - static/screens/duplicates.jsx
priority: medium
ordinal: 3100
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Goal: Port the Duplicates review screen.

## Read first
- swift-plan.md §10.2 #7 (Duplicates behavior), §9 (DuplicateDetector).
- Legacy static/screens/duplicates.jsx (271 lines) — pair list (original, candidate, similarity, captured, reason, compare), side-by-side compare with diff highlight, actions (unmark as duplicate → status saved; delete candidate), search, pair count.

## Implement (app/Views/Duplicates/)
- Pair list from DuplicateDetector.duplicateGroups() via @Query; compare view (all fields, differences highlighted); resolve via JobService.duplicates decision + status; delete candidate; search.

## Dependencies
Depends on task-045 (shell), task-046 (decision/status/delete), task-038 (DuplicateDetector pairs).

## Tests (AppUITests)
- Compare a pair; unmark (returns to saved, leaves the list); delete a candidate (with confirmation); search filters pairs.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Pair list with similarity + reason from DuplicateDetector
- [ ] #2 Side-by-side compare with difference highlighting
- [ ] #3 Unmark-as-duplicate and delete-candidate resolve via JobService; resolved pairs leave the list
- [ ] #4 Search filters; XCUITest covers compare/unmark/delete
<!-- AC:END -->
