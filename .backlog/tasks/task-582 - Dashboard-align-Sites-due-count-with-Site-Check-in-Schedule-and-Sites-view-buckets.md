---
id: TASK-582
title: >-
  Dashboard: align Sites due count with Site Check-in Schedule and Sites view
  buckets
status: To Do
assignee: []
created_date: '2026-06-21 03:11'
labels:
  - audit
  - dashboard
  - sites
  - workflow
dependencies: []
modified_files:
  - app/Views/Dashboard/DashboardView.swift
  - app/Views/Sites/SitesView.swift
  - core/Services/SiteService.swift
  - tests/CoreTests/SiteServiceTests.swift
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Finding: Dashboard housekeeping computes `sitesDue` as every non-excluded site where `nextReviewAt <= now`, treating `nil nextReviewAt` as due. The Site Check-in Schedule section excludes nil `nextReviewAt`, and `SitesView` shows those rows in a separate Not Yet Reviewed bucket. As a result, a dashboard can show `Sites due` for newly added sites while the schedule says `No sites scheduled`.

Why it matters: The dashboard uses one count to navigate users toward site maintenance, but the count combines two different states: due scheduled reviews and unscheduled/not-yet-reviewed sites. That makes the card and schedule disagree and hides which action is expected.

Suggested implementation: Extract a shared site review bucket policy with categories such as `overdue`, `dueSoon`, `scheduledLater`, `notYetReviewed`, and `excluded`. Use it in Dashboard housekeeping, Site Check-in Schedule, and SitesView. Either split the dashboard card into `Sites due` and `Not reviewed`, or make the schedule include and label not-yet-reviewed sites consistently.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 A site with `state == .notReviewed` and `nextReviewAt == nil` is not counted as a scheduled due site unless the dashboard labels it as not reviewed.
- [ ] #2 Dashboard Site Check-in Schedule and SitesView use the same bucket policy for overdue/due/not-reviewed/excluded states.
- [ ] #3 The dashboard card count and the rows visible after navigating to Sites reconcile for due scheduled sites.
- [ ] #4 Tests cover new nil-nextReviewAt sites, overdue reviewed sites, due-soon reviewed sites, and excluded sites.
<!-- AC:END -->
