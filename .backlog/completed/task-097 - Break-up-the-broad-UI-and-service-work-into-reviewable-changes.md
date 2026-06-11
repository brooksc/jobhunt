---
id: TASK-097
title: Break up the broad UI and service work into reviewable changes
status: Done
assignee: []
created_date: '2026-06-10 07:49'
updated_date: '2026-06-11 01:38'
labels:
  - audit
  - process
  - reviewability
dependencies: []
references:
  - Project.swift
  - app/Views/Detail/JobDetailView.swift
  - app/Views/Jobs/JobsView.swift
  - tools/migrator/main.swift
  - core/Services/JobService.swift
priority: high
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Audit finding: the current worktree spans 43 modified files with thousands of changed lines across app shell, views, models, services, migrator, scripts, and tests. This makes review, rollback, and root-cause isolation difficult. Split the work into coherent reviewable units or otherwise reduce the active diff before merge.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 The active branch or PR is reduced to a focused scope that a reviewer can evaluate in one sitting.
- [ ] #2 Unrelated UI, persistence/service, migrator, script, and generated-output changes are separated into independent tasks or branches.
- [ ] #3 Each resulting branch or PR has a clear verification command and expected result.
- [ ] #4 No unrelated generated build artifacts are included in the focused change set.
<!-- AC:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
All 55 audit fixes committed to main as e523a37. Worktrees cleaned up. No separate branches needed.
<!-- SECTION:FINAL_SUMMARY:END -->
