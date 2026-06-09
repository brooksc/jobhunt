---
id: TASK-068
title: 'HIG-5: Replace custom tab bar in JobDetailView with system TabView'
status: To Do
assignee: []
created_date: '2026-06-09 02:59'
labels:
  - hig
  - moderate
  - detail
dependencies: []
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
JobDetailView.swift implements a hand-rolled tab strip with HStack + underline Rectangle. Replace with TabView { }.tabViewStyle(.automatic) or a segmented Picker to get keyboard navigation, accessibility, and VoiceOver tab announcements.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Tab navigation uses system TabView or segmented Picker
- [ ] #2 Arrow keys / Tab key navigate between tabs
- [ ] #3 VoiceOver announces tab names correctly
<!-- AC:END -->
