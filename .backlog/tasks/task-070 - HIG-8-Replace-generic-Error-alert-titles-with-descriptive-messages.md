---
id: TASK-070
title: 'HIG-8: Replace generic "Error" alert titles with descriptive messages'
status: To Do
assignee: []
created_date: '2026-06-09 03:00'
labels:
  - hig
  - moderate
  - alerts
dependencies: []
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
DataQualityView.swift and NeedsActionView.swift use .alert("Error", isPresented:). HIG requires specific titles describing what went wrong. Audit all alert() calls and replace generic titles.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 No alert uses a generic 'Error' title
- [ ] #2 Each alert title describes the specific failure
<!-- AC:END -->
