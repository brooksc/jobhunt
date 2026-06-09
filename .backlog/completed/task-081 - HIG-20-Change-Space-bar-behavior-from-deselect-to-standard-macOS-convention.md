---
id: TASK-081
title: 'HIG-20: Change Space bar behavior from deselect to standard macOS convention'
status: Done
assignee: []
created_date: '2026-06-09 03:00'
updated_date: '2026-06-09 03:18'
labels:
  - hig
  - minor
  - keyboard
dependencies: []
priority: low
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
JobsView.swift uses .onKeyPress(.space) to deselect the current item or select the first item. macOS standard for Space in a list is Quick Look preview or no action. Deselecting on Space surprises users expecting scroll. Remove or change to Quick Look / detail toggle only on explicit selection.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Space no longer deselects items
- [ ] #2 If Space is kept, it opens Quick Look or does nothing unexpected
<!-- AC:END -->
