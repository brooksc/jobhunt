---
id: TASK-646
title: >-
  Surface upcoming interviews and offer decision deadlines outside the job
  detail
status: Done
assignee: []
created_date: '2026-07-25 21:34'
updated_date: '2026-07-25 21:44'
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
modified_files:
  - core/Services/MilestoneSchedule.swift
  - app/Views/Dashboard/DashboardMilestoneCard.swift
  - app/Views/Dashboard/DashboardView.swift
  - app/Views/Needs/NeedsActionMilestones.swift
  - app/Views/Needs/NeedsActionView.swift
  - core/Demo/DemoSeeder.swift
  - tests/CoreTests/MilestoneScheduleTests.swift
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
- [x] #1 Upcoming interviews (soonest first) surface on the Dashboard with company, title, round and date/time
- [x] #2 An offer with a decision deadline surfaces with days remaining, and is visually urgent as the deadline nears
- [x] #3 Interviews and offer deadlines appear in Needs Action alongside follow-ups
- [x] #4 Terminal jobs (archived/passed/closed/expired/duplicate) are excluded, consistent with FollowUpVisibility and the referral nudge filter
- [x] #5 Past interviews do not linger as actionable once their scheduled time has passed
- [x] #6 Clicking through navigates to the originating job
- [x] #7 Pure selection/ordering logic lives in JobhuntCore with unit tests (no UI-only derivation)
<!-- AC:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Shipped in c037b8c.

`MilestoneSchedule` (JobhuntCore) is the single source of selection/ordering, for the same reason `FollowUpVisibility` exists — the Dashboard card and Needs Action can't drift.

Two deliberate asymmetries, both tested:
- **Past interviews are dropped** — nothing to remember about one that already happened, and stale rows train the user to ignore the section.
- **Past offer deadlines are KEPT** and sort first as `.overdue` — a blown offer decision is precisely what must not silently vanish.

Urgency is classified on calendar-day boundaries rather than rolling hours, so "today" means the user's today (an interview at 10pm is today when seen at 9am; 00:30 tomorrow is not "13 hours away").

Needs Action uses a separate "Scheduled" section rather than the Overdue/Today/This-week buckets: those rows are follow-ups you complete or snooze, and you can't complete a Tuesday onsite — folding them in would break the screen's bulk actions and meaning (AC #3). The empty state is milestone-aware, so a scheduled interview with no follow-ups no longer reads "No follow-ups".

DemoSeeder seeds three interviews and an offer with a deadline so the card is populated in demo mode / screenshots.

Tests: `MilestoneScheduleTests` (10).

**Verification caveat:** logic is unit-tested and the app builds and launches, but I did not obtain a clean visual confirmation of the rendered card — repeated attempts at screen automation collided with the user's active session, so I stopped rather than keep interfering. Worth a human eyeball on the Dashboard and Needs Action.
<!-- SECTION:FINAL_SUMMARY:END -->
