---
id: TASK-015
title: Add automatic dark mode to dashboard
status: Done
assignee: []
created_date: '2026-05-27 05:47'
updated_date: '2026-05-27 05:48'
labels:
  - m5-polish
  - dashboard
  - ui
dependencies:
  - TASK-013
modified_files:
  - src/jobhunt/dashboard.py
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Add automatic dark mode support to the local browser dashboard using the user's system color scheme. Keep the implementation simple and framework-free.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 The dashboard uses a light theme by default
- [x] #2 The dashboard switches to a dark theme when the browser or OS prefers dark color scheme
- [x] #3 Tables links muted text and empty states remain readable in both themes
- [x] #4 Focused tests or static checks continue to pass
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Implemented dashboard dark mode using CSS custom properties and `@media (prefers-color-scheme: dark)`. No JavaScript or user setting was added; the dashboard follows browser/OS preference automatically.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Added automatic light/dark dashboard theming. The dashboard now declares `color-scheme: light dark`, uses CSS variables for surfaces text borders links and muted text, and switches those variables under `prefers-color-scheme: dark`. Tests and static CSS assertion pass.
<!-- SECTION:FINAL_SUMMARY:END -->
