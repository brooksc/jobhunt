---
id: TASK-078
title: 'HIG-16: Remove hardcoded profile header from sidebar'
status: Done
assignee: []
created_date: '2026-06-09 03:00'
updated_date: '2026-06-09 03:18'
labels:
  - hig
  - minor
  - sidebar
dependencies: []
priority: low
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Sidebar.swift profileSection hardcodes "Brooks Chambers" and "Senior / Staff · Remote-first" with no tap action or edit affordance. This non-navigable decorative header is not a standard macOS pattern and wastes sidebar space. Remove it or move to Settings.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Hardcoded profile section removed from sidebar
- [ ] #2 If user identity is needed, it is driven by settings data
<!-- AC:END -->
