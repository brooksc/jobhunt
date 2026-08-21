---
id: TASK-677
title: AppUITests has failed every weekly run since at least 2026-07-13
status: To Do
assignee: []
created_date: '2026-08-21 02:19'
labels:
  - ci
  - tests
  - tech-debt
dependencies: []
priority: medium
ordinal: 48000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
The scheduled UI-test workflow has failed 6 consecutive runs (2026-07-13 through 2026-08-17). Latest failure: WorkflowUITests.testArchive_seededJob_movesJobToArchived — 'Job's StatusChip should show Archived after archiving — seeded data has no pre-archived jobs'.

It predates the 2026-08 backlog run, so it is not a regression from that work, but it means the ONLY automated check on the app layer has been red and unwatched for six weeks. Everything shipped since has been verified by unit tests plus 'not verified: (visual)' notes, with the UI suite contributing nothing.

Either fix the seeded-data assumption and get the suite green, or if the suite is not worth maintaining, say so explicitly and stop running it — a permanently red scheduled job trains everyone to ignore it.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 The weekly AppUITests run is green, or the workflow is deliberately retired with a recorded reason
- [ ] #2 If kept, a red run is noticed — the result reaches someone rather than sitting in the Actions tab
<!-- AC:END -->
