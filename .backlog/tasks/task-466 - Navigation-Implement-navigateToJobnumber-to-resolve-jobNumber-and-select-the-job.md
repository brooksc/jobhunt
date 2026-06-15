---
id: TASK-466
title: >-
  Navigation: Implement navigateToJob(number:) to resolve jobNumber and select
  the job
status: Done
assignee: []
created_date: '2026-06-15 03:38'
updated_date: '2026-06-15 06:33'
labels:
  - bug
  - navigation
  - app
dependencies: []
references:
  - app/Shell/Router.swift
  - app/Shell/PlatformIntegration.swift
priority: high
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
`Router.navigateToJob(number _: Int)` discards its argument and only sets `selectedSection = .jobs; selectedJobID = nil`. Every caller that wants to open a specific job lands on the Jobs section with nothing selected: deep links `jobhunt://jobs/N` (PlatformIntegration.swift:54), HTTP `/api/app/focus` (PlatformIntegration.swift:62), and notification taps for strong-match / unavailable / processing alerts (PlatformIntegration.swift:203). There is also a type mismatch: notifications carry `jobNumber` (Int) but `Router.selectedJobID` is the `Job.id` String (UUID), and no jobNumber-to-id resolution exists anywhere. The resolution needs a model lookup (Job where jobNumber == N) and so belongs somewhere with ModelContext/AppServices access rather than the plain Router.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 navigateToJob(number:) resolves the jobNumber to its Job.id and sets selectedJobID to that value
- [x] #2 Deep link jobhunt://jobs/N selects job number N in the Jobs section
- [x] #3 HTTP /api/app/focus for a job number selects that job
- [x] #4 Notification taps (strong-match, unavailable, processing) open the referenced job
- [x] #5 Navigation to a non-existent job number is handled gracefully (lands on Jobs with no selection, no crash)
<!-- AC:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Implemented and committed in a8b2338. Router.navigateToJob(number:) (which discarded its arg) replaced by Router.selectJob(id:); PlatformIntegration now resolves jobNumber→Job.id via its modelContainer and selects it, with graceful fallback to the Jobs section when the number doesn't resolve. Fixes deep links, /api/app/focus, and notification taps. (Backlog status missed at the time; verified present and marking Done.)
<!-- SECTION:FINAL_SUMMARY:END -->
