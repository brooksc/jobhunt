---
id: TASK-302
title: 'Dashboard: Hide excluded sites from site check-in schedule'
status: Done
assignee: []
created_date: '2026-06-12 05:01'
updated_date: '2026-06-12 05:47'
labels:
  - audit
  - dashboard
  - sites
dependencies: []
references:
  - app/Views/Sites/SitesView.swift
  - app/Views/Dashboard/DashboardView.swift
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
SitesView filters out excluded sites from due/review sections, but the dashboard site check-in schedule includes all sites with nextReviewAt. Excluded sites can still appear as scheduled work.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Dashboard site schedule applies the same excluded-site policy as the Sites view.
- [ ] #2 Excluded sites do not appear in overdue, due-soon, or dashboard check-in schedules.
- [ ] #3 Add a regression test or extracted filtering test for excluded sites.
<!-- AC:END -->
