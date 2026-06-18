---
id: TASK-501
title: 'Structured interview/offer tracking (dates, interviewer, offer details)'
status: To Do
assignee: []
created_date: '2026-06-18 23:06'
labels:
  - ux
  - apply-workflow
  - feature
dependencies: []
priority: low
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Status can be set to Interview/Offer but there's nowhere to record the interview date/interviewer or offer details — it all goes into freeform notes. Add structured capture (interview date/time, interviewer, location; offer date/title/salary/notes) as JobEvent records, with quick-action buttons when the status is Interview/Offer. Punted from the workflow review (low priority for now).

References: app/Views/Detail/JobDetailView.swift (Timeline tab), core/Models/JobEvent.swift, core/Services/JobService.swift.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Recording an interview captures a date and optional interviewer/location as a timeline event
- [ ] #2 Recording an offer captures structured fields (date, title, salary, notes)
- [ ] #3 These surface in the Timeline and are not just freeform text
<!-- AC:END -->
