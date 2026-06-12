---
id: TASK-279
title: 'Application workflow: Prefer extracted application URL in detail apply links'
status: To Do
assignee: []
created_date: '2026-06-12 03:36'
labels:
  - audit
  - application-workflow
  - url
  - ux
dependencies: []
references:
  - app/Views/Detail/JobDetailView.swift
  - app/Views/Dashboard/DashboardView.swift
priority: high
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Dashboard apply links prefer job.applicationURL before the captured source URL, but detail header/footer/raw actions prefer capture.url before applicationURL. Align link precedence so the primary application workflow opens the extracted apply URL when available.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 All primary Apply/Open application actions use job.applicationURL before capture/canonical source URL when applicationURL is present.
- [ ] #2 Source-posting actions remain available and are clearly labeled separately from Apply actions.
- [ ] #3 Tests or UI assertions cover jobs with both source URL and application URL.
<!-- AC:END -->
