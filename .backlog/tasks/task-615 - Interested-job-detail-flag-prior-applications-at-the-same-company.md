---
id: TASK-615
title: 'Interested job detail: flag prior applications at the same company'
status: Done
assignee: []
created_date: '2026-07-22 19:02'
updated_date: '2026-07-23 04:48'
labels:
  - workflow
  - job-detail
  - applications
  - ux
dependencies: []
references:
  - app/Views/Detail/JobDetailView.swift
  - app/Shell/Router.swift
  - core/Models/Job.swift
  - core/Services/DuplicateDetector.swift
  - core/Services/JobService.swift
  - core/Services/BackgroundStore.swift
  - tests/CoreTests/JobServiceTests.swift
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
When viewing an Interested job, show an application-history warning if other jobs at the same normalized company were previously applied to. This is an informational safeguard against applying twice to the same role; it must not block the user from applying.

Match companies using a shared, conservative normalization rule that handles case, punctuation, and common legal suffixes (for example, “Acme” and “Acme, Inc.”) without treating empty/generic company tokens or merely similar company names as equal. Where useful, corroborate ambiguous names with the source/company domain.

A prior job counts as applied when `appliedAt` is present, regardless of its current status, so later Interview, Offer, Rejected, Archived, Closed, or Expired transitions do not erase application history. For legacy records without `appliedAt`, statuses that directly imply an application (`applied`, `interview`, `offer`, or `rejected`) may be used as a fallback.

In the Interested job’s detail Overview, show a compact warning summarizing the number of prior applications. List each matching job’s title, current status, and application date when known, with an action to open that job. If a prior title is an exact or strong normalized match for the current title, elevate the message to “Possible repeat application” and identify the matching role; otherwise say that the user has applied to other roles at the company.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 An Interested job’s detail view shows a prior-application warning when at least one other job at the same normalized company has application history.
- [ ] #2 Application history primarily uses a non-nil `appliedAt` and remains visible after the prior job moves to Interview, Offer, Rejected, Archived, Closed, or Expired.
- [ ] #3 Legacy jobs without `appliedAt` are included when their current status directly implies an application: Applied, Interview, Offer, or Rejected.
- [ ] #4 Company matching handles case, punctuation, and common legal suffix variations while rejecting empty/generic company values and unrelated companies with superficially similar names.
- [ ] #5 The warning lists each prior job’s title, current status, and application date when available, and selecting an entry navigates to that job’s detail view.
- [ ] #6 An exact or strong normalized title match is labeled as a possible repeat application; different titles are presented as other applications at the same company.
- [ ] #7 The warning is hidden when there are no matches and when the currently viewed job is not Interested.
- [ ] #8 The current job is excluded from its own match set, and duplicate records do not cause the same prior application to be listed more than once.
- [ ] #9 The warning does not prevent or silently alter the Apply action.
- [ ] #10 Focused tests cover company normalization, application-history status transitions, legacy fallback, same-role emphasis, different-role messaging, navigation, self-exclusion, duplicate suppression, and non-Interested visibility.
<!-- AC:END -->
