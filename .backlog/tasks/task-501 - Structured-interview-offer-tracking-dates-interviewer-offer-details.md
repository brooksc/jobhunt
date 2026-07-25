---
id: TASK-501
title: 'Structured interview/offer tracking (dates, interviewer, offer details)'
status: Done
assignee: []
created_date: '2026-06-18 23:06'
updated_date: '2026-07-25 20:17'
labels:
  - ux
  - apply-workflow
  - feature
dependencies: []
modified_files:
  - core/Models/InterviewRecord.swift
  - core/Models/OfferRecord.swift
  - core/Models/Schema.swift
  - core/Services/BackgroundStore.swift
  - core/Services/JobService.swift
  - app/Views/Milestones/MilestoneViews.swift
  - app/Views/Milestones/MilestoneEditors.swift
  - app/Views/Detail/JobDetailView.swift
  - tests/CoreTests/MilestoneStoreTests.swift
priority: low
ordinal: 20000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Status can be set to Interview/Offer but there's nowhere to record the interview date/interviewer or offer details — it all goes into freeform notes. Add structured capture (interview date/time, interviewer, location; offer date/title/salary/notes) as JobEvent records, with quick-action buttons when the status is Interview/Offer. Punted from the workflow review (low priority for now).

References: app/Views/Detail/JobDetailView.swift (Timeline tab), core/Models/JobEvent.swift, core/Services/JobService.swift.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Recording an interview captures a date and optional interviewer/location as a timeline event
- [x] #2 Recording an offer captures structured fields (date, title, salary, notes)
- [x] #3 These surface in the Timeline and are not just freeform text
<!-- AC:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Shipped in cb57745.

Two new models keyed by `jobID` with no SwiftData relationship (the frozen `Job` is untouched; new models in `SchemaV1.models` are a non-breaking change), following the `ReferralAttempt` pattern:

- **InterviewRecord** — many per job: round (screen / hiring manager / technical / panel / onsite / final), scheduled date+time, interviewer, location, note.
- **OfferRecord** — at most one per job, upserted on `jobID`: offer date, title actually offered, base salary as a whole-currency Int (consistent with `Job.salaryMin/Max`), free-text equity/bonus, decision deadline, note.

Each record mirrors into exactly one `JobEvent`, reusing the existing `interview`/`offer` event types the Timeline already renders with their own icon and colour (AC #3). The event id is derived from the record, so editing a round corrects the existing Timeline entry rather than appending a second, and deleting takes it with it. Milestone events deliberately carry no recap category — the status transition to Interview/Offer is what counts there, so the daily recap can't double-count.

Applies the conventions from the TASK-644 referral audit: job-must-exist guard (`BackgroundStoreError.notFound`), trimmed/empty-to-nil strings, decision deadline clamped to the offer date, shared `SheetDateField`, first-responder claim on appear, and `JobService.delete` cascade.

The section renders at Interview/Offer or whenever records exist, so nothing becomes unreachable if the status is later moved back.

Tests: `MilestoneStoreTests` (10) — upsert, single-mirrored-event, multi-round coexistence, offer upsert, deadline clamping, missing-job guard, cascade, and recap exclusion.

**Known gap (follow-up):** nothing surfaces these outside the job detail — no upcoming-interview or offer-deadline surfacing on the Dashboard / Needs Action.
<!-- SECTION:FINAL_SUMMARY:END -->
