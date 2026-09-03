---
id: TASK-691
title: >-
  Selecting an Expired job from the referrals list resets the filter to New and
  loses the selection
status: To Do
assignee: []
created_date: '2026-08-31 16:55'
labels: []
dependencies: []
priority: medium
type: bug
ordinal: 91000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Reported 2026-08-31. Clicking a job with status Expired from the referrals / "Add: contact method, contact type, website/email, result" list (observed on Pulumi — Principal Product Manager, job #130, Jul 6 2026, Expired) navigates to Jobs but switches the filter to **New** and shows no selected job.

Expected: navigating to a specific job selects that job and shows its detail, whatever its status — the filter should widen (or be cleared) to include the target rather than the target being dropped because it doesn't match the current filter.

Likely cause: the navigation sets the job selection before/independently of the filter state, and `filteredJobs` (JobsView) excludes the Expired row, so `selectedJobIDs` refers to a row the List isn't rendering. Same class of issue would affect any deep link to an archived/expired job.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Selecting an Expired job from the referrals list opens that job's detail with it selected
- [ ] #2 The status filter is cleared or widened so the target job is visible in the list, rather than the selection being silently dropped
- [ ] #3 Behaviour holds for every non-New status reachable this way (archived, expired, applied)
<!-- AC:END -->
