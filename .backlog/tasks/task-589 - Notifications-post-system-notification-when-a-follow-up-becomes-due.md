---
id: TASK-589
title: 'Notifications: post system notification when a follow-up becomes due'
status: To Do
assignee: []
created_date: '2026-07-02 21:52'
updated_date: '2026-07-21 22:59'
labels: []
dependencies:
  - TASK-502
references:
  - app/Platform/PlatformIntegration.swift
  - core/App/RuntimeTaskController.swift
  - core/Models/JobAction.swift
priority: low
ordinal: 38000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
**Opportunity:** Follow-ups (JobAction with a dueAt date) only surface if the user opens the Needs Action view. The app already has a full notification pipeline (ready-to-review, job-unavailable in `PlatformIntegration`) and a background loop for availability checking. Posting a system notification when a follow-up's dueAt arrives closes the loop on the feature's purpose.

**How to implement:**
1. In `RuntimeTaskController` (or alongside the availability-check timer), add a periodic check (every ~15 min is fine) that queries for `JobAction` records where `dueAt <= now && !completed && snoozedUntil == nil || snoozedUntil <= now`.
2. Track which actions have already been notified (either a `notifiedAt` field on `JobAction`, or a `Set<UUID>` in memory since it resets on relaunch — the latter is simpler).
3. Call `PlatformIntegration.notify(title: "Follow-up due", body: "\(job.title) at \(job.company)")` with a deep link to the job (`jobhunt://jobs/<number>`).
4. Cap notifications per check at ~5 to avoid flooding (report "5 follow-ups due, tap to see all" for larger batches).

**No new model changes needed.** `JobAction.dueAt` and `snoozedUntil` already exist.

**Note:** This is parked — no urgency. Implement after TASK-502 (snooze UX improvements) so the snooze behavior is settled before notifications reference it.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 System notification fires within one check cycle (~15 min) of a follow-up's dueAt passing
- [ ] #2 Snooze is respected: snoozed follow-ups don't notify until snoozedUntil passes
- [ ] #3 Already-notified actions don't re-notify on the next cycle
- [ ] #4 Notification deep-links to the relevant job
<!-- AC:END -->
