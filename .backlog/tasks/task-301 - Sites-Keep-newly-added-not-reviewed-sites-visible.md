---
id: TASK-301
title: 'Sites: Keep newly added not-reviewed sites visible'
status: To Do
assignee: []
created_date: '2026-06-12 05:01'
labels:
  - audit
  - sites
  - ux
dependencies: []
references:
  - core/Services/SiteService.swift
  - app/Views/Sites/SitesView.swift
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
SiteService.createSite creates a notReviewed site with nextReviewAt set to now plus the interval. SitesView only shows not-reviewed sites when nextReviewAt is nil, so a new site with the default 14-day interval can appear in no section until it becomes due soon.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Newly added notReviewed sites are visible in the Sites view immediately after creation.
- [ ] #2 Section logic clearly distinguishes not reviewed, due soon, overdue, reviewed, and excluded states.
- [ ] #3 Add a focused view-model or filtering test for the default newly added site case.
<!-- AC:END -->
