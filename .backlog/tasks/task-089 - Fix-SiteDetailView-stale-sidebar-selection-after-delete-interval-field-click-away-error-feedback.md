---
id: TASK-089
title: >-
  Fix SiteDetailView: stale sidebar selection after delete, interval field
  click-away, error feedback
status: To Do
assignee: []
created_date: '2026-06-10 07:31'
labels:
  - bug
  - ui-audit
dependencies: []
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
HIGH: After `deleteSite()`, `router.selectedSiteID` is never cleared. Sidebar continues highlighting the deleted row. Fix: set `router.selectedSiteID = nil` after successful delete.

MEDIUM: Interval days TextField discards edits on click-away — `.onSubmit` only, no `.onChange`/focus-loss handler. Fix: save on focus loss using `.onSubmit` + focused state or `.onChange`.

MEDIUM: Invalid interval input silently resets field with no error message. Fix: set `errorMessage` when input fails validation.

Files: `app/Views/Sites/SiteDetailView.swift`
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 After deleting a site, sidebar selection is cleared and detail pane shows empty state
- [ ] #2 Editing interval days and clicking away saves the value (or shows error if invalid)
- [ ] #3 Invalid interval input shows an error message to the user
<!-- AC:END -->
