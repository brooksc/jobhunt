---
id: TASK-289
title: 'Saved searches: Merge multiple recent-day tokens deterministically'
status: To Do
assignee: []
created_date: '2026-06-12 03:44'
labels:
  - audit
  - saved-search
  - search
  - filters
dependencies: []
references:
  - app/Views/Jobs/SaveSearchSheet.swift
  - app/Views/Jobs/JobSearchToken.swift
priority: low
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
SaveSearchSheet merges numeric thresholds using the stricter max value, but recentDays keeps the first token only. When multiple recent filters exist, save the most restrictive recent window or prevent duplicates.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Multiple recent-day tokens save deterministically as the intended most restrictive filter, or duplicate recent tokens are prevented.
- [ ] #2 The save-search summary matches the actual persisted recentDays value.
- [ ] #3 Tests cover saving Last 30 days plus Last 7 days in either token order.
<!-- AC:END -->
