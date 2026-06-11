---
id: TASK-172
title: 'Error handling: Preserve duplicate-resolution state when mutations fail'
status: Done
assignee: []
created_date: '2026-06-11 21:44'
updated_date: '2026-06-11 22:20'
labels:
  - audit
  - error-handling
  - duplicates
  - workflow
dependencies: []
references:
  - app/Views/Duplicates/DuplicatesView.swift
  - core/Services/JobService.swift
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Duplicate-resolution actions clear `selectedPairID`, suppress service errors, and refresh the duplicate list after unmark/delete commands. If a mutation fails, the UI can appear to have resolved the duplicate while no data changed. Handle failures explicitly and only clear selection after successful mutation or show a clear partial-failure state.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Duplicate unmark/delete failures are visible to the user.
- [ ] #2 The selected duplicate pair is not cleared before a failed mutation is handled.
- [ ] #3 Tests or previewable view-state coverage verify success and failure behavior for duplicate actions.
<!-- AC:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Fixed `DuplicatesView.handleUnmark` and `handleDelete` to clear `selectedPairID` only after a successful mutation. Added `@State private var actionError: String?` and a `.safeAreaInset(edge: .top)` error banner that mirrors the pattern used in LLMQueueView. If mutation throws, the pair stays selected and the error is shown inline. On success, `actionError` is also cleared.
<!-- SECTION:FINAL_SUMMARY:END -->
