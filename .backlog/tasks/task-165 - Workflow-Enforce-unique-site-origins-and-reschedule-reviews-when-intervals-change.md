---
id: TASK-165
title: >-
  Workflow: Enforce unique site origins and reschedule reviews when intervals
  change
status: Done
assignee: []
created_date: '2026-06-11 20:57'
updated_date: '2026-06-11 21:41'
labels:
  - audit
  - workflow
  - sites
  - data-integrity
dependencies: []
references:
  - core/Services/SiteService.swift
  - core/Models/Site.swift
  - app/Views/Sites
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
`SiteService.createSite` inserts a new site for an origin without checking whether that origin already exists, and `updateSite` can change `intervalDays` without recomputing `nextReviewAt`. This can create duplicate site rows and schedules that do not reflect the user’s new interval until a later review event.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Creating or adding a site with an existing origin updates or rejects the duplicate consistently.
- [ ] #2 Changing review interval updates `nextReviewAt` according to the chosen scheduling rule.
- [ ] #3 Tests cover duplicate origin handling and interval-change scheduling.
<!-- AC:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Fixed two issues in SiteService: (1) `createSite` now fetches existing sites and returns the existing ID (updating companyName if provided) when a duplicate origin is detected, preventing extra rows. (2) `updateSite` now recomputes `nextReviewAt = lastReviewedAt + newIntervalDays` (falling back to `now + newIntervalDays` when never reviewed) whenever `intervalDays` is changed. Added `testCreateSite_duplicateOrigin_returnsExistingID` and `testUpdateSite_intervalChange_recomputesNextReviewAt` in JobServiceTests.
<!-- SECTION:FINAL_SUMMARY:END -->
