---
id: TASK-646
title: >-
  Surface upcoming interviews and offer decision deadlines outside the job
  detail
status: To Do
assignee: []
created_date: '2026-07-25 21:34'
labels:
  - dashboard
  - workflow
  - apply-workflow
dependencies: []
references:
  - app/Views/Milestones/MilestoneViews.swift
  - app/Views/Dashboard/DashboardReferralCard.swift
  - core/Models/FollowUpVisibility.swift
  - app/Views/Needs/NeedsActionView.swift
  - core/Models/InterviewRecord.swift
  - core/Models/OfferRecord.swift
priority: high
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
TASK-501 added `InterviewRecord` (with `scheduledAt`) and `OfferRecord` (with `decisionBy`), but they are read by exactly two files — both in the job-detail Milestones views. Nothing in the Dashboard, Needs Action, or the Sidebar reads them.

Consequence: an interview scheduled for next Tuesday is invisible unless the user opens that specific job, and an offer's decision deadline — the most time-critical date in a job search, and unrecoverable if missed — is equally invisible. Meanwhile the app already nudges about stale *referrals*, so referrals nag and interviews don't, which is backwards.

Follow the established patterns rather than inventing new ones: `DashboardReferralCard` for the card shape and `FollowUpVisibility` (TASK-577) for actionability, including excluding terminal jobs the way referral nudges now do.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Upcoming interviews (soonest first) surface on the Dashboard with company, title, round and date/time
- [ ] #2 An offer with a decision deadline surfaces with days remaining, and is visually urgent as the deadline nears
- [ ] #3 Interviews and offer deadlines appear in Needs Action alongside follow-ups
- [ ] #4 Terminal jobs (archived/passed/closed/expired/duplicate) are excluded, consistent with FollowUpVisibility and the referral nudge filter
- [ ] #5 Past interviews do not linger as actionable once their scheduled time has passed
- [ ] #6 Clicking through navigates to the originating job
- [ ] #7 Pure selection/ordering logic lives in JobhuntCore with unit tests (no UI-only derivation)
<!-- AC:END -->
