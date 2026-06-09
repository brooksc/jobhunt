---
id: TASK-080
title: 'HIG-19: Add accessibility annotations to unread indicator dot in job rows'
status: Done
assignee: []
created_date: '2026-06-09 03:00'
updated_date: '2026-06-09 03:18'
labels:
  - hig
  - minor
  - accessibility
dependencies: []
priority: low
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
The 5pt unread dot Circle in JobListRow has no accessibility label. VoiceOver users get no indication of unread status. Add .accessibilityLabel("Unread") or combine with the row's accessibility value.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Unread dot has accessibilityLabel or accessibilityHidden with unread status included in row's accessibilityValue
<!-- AC:END -->
