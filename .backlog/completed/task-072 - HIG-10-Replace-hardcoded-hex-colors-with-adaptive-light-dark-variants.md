---
id: TASK-072
title: 'HIG-10: Replace hardcoded hex colors with adaptive light/dark variants'
status: Done
assignee: []
created_date: '2026-06-09 03:00'
updated_date: '2026-06-09 03:18'
labels:
  - hig
  - moderate
  - color
  - accessibility
dependencies: []
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Theme.swift defines status and accent colors as raw Color(red:green:blue:) values that don't adapt to dark mode. Move colors to asset catalog with Any/Dark variants, or use Color(light:dark:) initializer for adaptive values.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 All status colors readable in both light and dark mode
- [ ] #2 Archived status color visible on dark backgrounds
- [ ] #3 Colors defined in asset catalog or with adaptive initializer
<!-- AC:END -->
