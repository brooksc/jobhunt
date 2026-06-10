---
id: TASK-094
title: >-
  Fix ResumesTab: active toggle tap propagates to edit sheet; delete alert
  fragile on empty list
status: Done
assignee: []
created_date: '2026-06-10 07:32'
updated_date: '2026-06-10 22:24'
labels:
  - bug
  - ui-audit
dependencies: []
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
MEDIUM: Tapping the circle/checkmark icon (set active) also fires the parent row's `onTapGesture` (open edit sheet). Fix: add `.onTapGesture { }` to the icon button with a proper gesture that stops propagation, or use a Button with explicit action instead of stacking tap gestures.

MEDIUM: Delete alert auto-promotes another resume as active, but if `resumes` is empty at confirmation time (edge case), no resume is promoted and user gets no feedback. Fix: after delete, check if any resume remains active and show appropriate feedback.

Files: `app/Views/Settings/ResumesTab.swift`
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Tapping the active toggle icon only sets the resume active without opening edit sheet
- [ ] #2 Deleting the last resume shows appropriate warning that no active resume will exist
<!-- AC:END -->
