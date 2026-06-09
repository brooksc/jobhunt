---
id: TASK-076
title: 'HIG-14: Remove .textCase(.uppercase) and tracking from sidebar section headers'
status: To Do
assignee: []
created_date: '2026-06-09 03:00'
labels:
  - hig
  - minor
  - sidebar
  - typography
dependencies: []
priority: low
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
navSectionLabel() uses .textCase(.uppercase).tracking(0.4) which is an iOS/web pattern. macOS sidebars (Finder, Mail) use mixed-case bold section labels without uppercase transformation.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Section headers are mixed-case
- [ ] #2 .textCase(.uppercase) and .tracking() removed from navSectionLabel
<!-- AC:END -->
