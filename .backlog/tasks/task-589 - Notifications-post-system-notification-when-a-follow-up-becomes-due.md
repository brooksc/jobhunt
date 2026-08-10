---
id: TASK-589
title: 'Notifications: post system notification when a follow-up becomes due'
status: Done
assignee: []
created_date: '2026-07-02 21:52'
updated_date: '2026-08-10 00:29'
labels: []
dependencies:
  - TASK-502
references:
  - app/Platform/PlatformIntegration.swift
  - core/App/RuntimeTaskController.swift
  - core/Models/JobAction.swift
modified_files:
  - core/Services/DueFollowUps.swift
  - core/Services/BackgroundStore.swift
  - app/Platform/PlatformIntegration.swift
  - app/Shell/AppServices.swift
  - app/JobhuntApp.swift
  - tests/CoreTests/DueFollowUpsTests.swift
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
- [x] #1 System notification fires within one check cycle (~15 min) of a follow-up's dueAt passing
- [x] #2 Snooze is respected: snoozed follow-ups don't notify until snoozedUntil passes
- [x] #3 Already-notified actions don't re-notify on the next cycle
- [x] #4 Notification deep-links to the relevant job
<!-- AC:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Unblocked once TASK-502 landed. `DueFollowUps` (Core) decides due-ness and composes the message; `BackgroundStore.dueFollowUps()` flattens the rows (`JobAction` isn't Sendable); a 15-minute loop in `startRuntime` posts through a new `PlatformIntegration.notifyFollowUpsDue`.

#1 15-minute cycle, first pass 60s after launch rather than immediately — at launch the store is still opening and the user hasn't seen the window yet.

#2 A live snooze suppresses; an **expired** snooze counts as due again. That direction matters more than it looks: reading a stale `snoozedUntil` as "still snoozed" would silence the follow-up permanently, the worst available failure for a reminder. Both directions are tested.

#3 Notified ids are held in memory, per the task's own suggestion. Re-reminding once per launch is reasonable behaviour for a reminder, and a persisted flag would need a migration plus a rule for clearing it — the stale-flag shape CLAUDE.md warns about, which already caused the capture re-clean bug.

#4 One due follow-up deep-links to its job via the existing `jobNumber` userInfo route. Several route to Needs Action instead: opening an arbitrary one of five is worse than opening none. Past five it summarizes, but the notification still covers **every** id — marking only the named ones would re-notify the remainder on every subsequent cycle, forever.

`AppServices` gained a weak `platformIntegration` set by the launch owner, so the runtime loops can post without owning the observer (a strong handle there would be a retain cycle through the app's two longest-lived types).

11 tests. Gate: fast gate TEST SUCCEEDED, swiftlint 0 violations in 344 files, swiftformat clean, warning ratchet 58/58.

not verified: no notification was actually posted and clicked — that needs a running app with notification permission granted. The due-ness rules, message composition and id-coverage are unit-tested; the loop and the click route are compile-checked only.
<!-- SECTION:FINAL_SUMMARY:END -->
