---
id: TASK-084
title: >-
  Fix JobDetailView: Prev/Next dead, Note button no sheet, Tailor empty action,
  misc medium bugs
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
Multiple bugs in JobDetailView:

HIGH: Prev/Next chevron buttons post NotificationCenter notifications that have no observer anywhere. Fix: implement navigation directly (pass a navigate callback from parent, or wire up an observer in ContentView/parent).

HIGH: Note button sets `showNoteSheet = true` but no `.sheet(isPresented: $showNoteSheet)` modifier exists. Fix: either add the sheet or scroll/focus the inline timeline composer.

HIGH: `Tailor resume to this role` button has empty `{ }` action. Fix: implement or show a not-yet-implemented alert.

MEDIUM: Archive and Mark Unavailable buttons fire immediately — add confirmationDialog.

MEDIUM: Unmark as Duplicate hardcodes `status = .pursuing`, destroying prior status. Fix: restore original status or don't overwrite it.

MEDIUM: Note composer advertises ⌘↵ shortcut but `.onSubmit` fires on plain Return (inserts newline in multiline field). Fix the keyboard handler.

LOW: Skill remove uses `removeAll { $0 == skill }` — removes all duplicates. Fix: remove by index.

LOW: Re-score button not disabled while isBusy.

Files: `app/Views/Detail/JobDetailView.swift`
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Prev/Next buttons navigate between jobs in the current list
- [ ] #2 Note button opens a sheet or focuses inline composer
- [ ] #3 Tailor button shows meaningful UI (sheet or 'coming soon' alert)
- [ ] #4 Archive and Mark Unavailable require confirmation
- [ ] #5 Unmark as Duplicate preserves original job status
- [ ] #6 Note composer ⌘↵ shortcut matches actual behavior
- [ ] #7 Skill remove deletes only the tapped instance
- [ ] #8 Re-score button disabled while isBusy
<!-- AC:END -->
