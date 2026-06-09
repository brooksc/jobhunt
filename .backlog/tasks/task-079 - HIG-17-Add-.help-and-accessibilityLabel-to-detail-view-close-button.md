---
id: TASK-079
title: 'HIG-17: Add .help() and accessibilityLabel to detail view close button'
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
DetailHeader in JobDetailView.swift has a plain xmark Button with no .help() or accessibilityLabel. VoiceOver announces it as "xmark". Add .help("Close") and .accessibilityLabel("Close").
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 .help("Close") added to xmark button
- [ ] #2 .accessibilityLabel("Close") added
- [ ] #3 VoiceOver announces 'Close' not 'xmark'
<!-- AC:END -->
