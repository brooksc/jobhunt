---
id: TASK-582
title: >-
  Dashboard: align Sites due count with Site Check-in Schedule and Sites view
  buckets
status: Done
assignee: []
created_date: '2026-06-21 03:11'
updated_date: '2026-06-26 02:46'
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
- [x] #1 A site with `state == .notReviewed` and `nextReviewAt == nil` is not counted as a scheduled due site unless the dashboard labels it as not reviewed.
- [x] #2 Dashboard Site Check-in Schedule and SitesView use the same bucket policy for overdue/due/not-reviewed/excluded states.
- [x] #3 The dashboard card count and the rows visible after navigating to Sites reconcile for due scheduled sites.
- [x] #4 Tests cover new nil-nextReviewAt sites, overdue reviewed sites, due-soon reviewed sites, and excluded sites.
<!-- AC:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Added SiteReviewBucket.classify(state:nextReviewAt:now:dueSoonDays:) → overdue / dueSoon / scheduledLater / notYetReviewed / excluded. Dashboard "Sites due" now counts only .overdue, so a brand-new site (nil nextReviewAt → notYetReviewed) is no longer counted as due (AC#1). The dashboard Site Check-in Schedule and all SitesView sections (overdue/dueSoon/reviewed→scheduledLater/notYetReviewed/excluded) derive from the same classifier (AC#2), so the card count reconciles with the Overdue rows shown after navigating (AC#3). Tests (SiteReviewBucketTests) cover nil-date, overdue, due-soon, scheduled-later, and excluded (AC#4). Build + lint clean; SiteReviewBucketTests pass.
<!-- SECTION:FINAL_SUMMARY:END -->
