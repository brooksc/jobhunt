---
id: TASK-673
title: >-
  Background LinkedIn availability checking so a check isn't gated on the
  per-run cap
status: Done
assignee: []
created_date: '2026-08-20 20:39'
updated_date: '2026-08-22 20:41'
labels:
  - availability
  - linkedin
  - ux
dependencies: []
priority: medium
ordinal: 44000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Follow-up from the archive expiration work (TASK-672 sweep). LinkedIn is checked 12 per run by rotation because guest requests get throttled, and a throttled check reads as "available" — so a run over 400 archived jobs checks 342 and holds 58 back. The numbers now agree across the menu, the progress dialog and the summary, and the deferred postings are reported as "not due for checking this run", so nothing is hidden. What's still unsatisfying is the workflow: fully sweeping ~70 LinkedIn postings takes ~6 manual runs.

Idea from the user: keep the per-run cap for the foreground check (so results arrive promptly for everything else), and drain the LinkedIn backlog in the BACKGROUND over time — a slow drip that respects the same pacing and backoff. The user sees what's immediately available, and LinkedIn results land as they come.

Design questions to settle before building:
- Where does the drip live? The existing availability loop runs on an interval gate keyed to availabilityLastAutoCheckAt, which is about the scheduled sweep of Interested/Applied — LinkedIn drainage for ARCHIVED jobs is a different population and must not reset that gate (see AvailabilityChecker.coversScheduledSweep).
- How does a result surface once the user has closed the confirmation sheet? A background 'gone' finding for an archived job has no obvious home — the Needs Action list is for live work, and a notification per posting would be noise.
- Should the drip be opt-in? It makes ongoing background requests to LinkedIn on the user's IP.
- Does it stop when the backlog is drained, or re-check on a staleness interval?

Not a bug: the current behaviour is correct and now self-explanatory. This is a workflow improvement.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 The foreground check keeps the per-run LinkedIn cap and its pacing/backoff
- [x] #2 LinkedIn postings outside a run's window are drained in the background without resetting the scheduled sweep's interval gate
- [x] #3 A background 'gone' finding for an archived job surfaces somewhere the user will see it, without one notification per posting
- [x] #4 The behaviour is opt-in or clearly disclosed, since it makes ongoing requests to LinkedIn from the user's IP
- [x] #5 Drainage stops when the backlog is clear and resumes on a staleness interval rather than looping forever
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Implemented in the session that filed it, scoped to what the user asked for: background drain of whatever a check couldn't answer, plus one macOS notification at the end.

- AvailabilityBacklog (Core, 8 tests): retryable reasons are notCheckedThisRun / rateLimited / unreachable only — a bot-challenge page and a client-rendered shell answer identically twenty minutes later, and noURL can never be checked. Pending set is REPLACED per pass so the drain converges; findings accumulate deduplicated.
- AppServices.availabilityDrainTask: every 5 min, foreground-only, 12 postings per pass (matched to the LinkedIn cap — these are the hosts that objected to being asked quickly). Gated on availability_auto_check_enabled, so the existing toggle turns it off.
- Seeded by any run: the on-demand Jobs-list check hands its sweep to the backlog.
- PlatformIntegration.notifyBacklogDrained: fires once when the backlog empties AND there is something to report. NOT rate-limited like the daily nudge — it reports the end of a finite piece of work.
- Clicking the notification opens the confirmation sheet with the accumulated findings instead of re-running the whole check.

Open AC #2 (must not reset the scheduled sweep's interval gate) holds: the drain calls findGoneJobsRotating directly and never writes availability_last_auto_check_at.

not verified: (visual) — the notification firing and its click path need a live desktop and a drain that takes ~10+ minutes to complete.

REMAINING, not done: survival across relaunch. The backlog is in-memory because nothing records per-job check history — that's TASK-674, which this depends on for a durable version.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Complete. The remaining piece from the first pass — surviving a relaunch — landed once TASK-674 gave the store per-job verdicts to read back.

**Durability without a new table.** A job persisted as `.unverified` for a retryable reason *is* a job still owed an answer, so `BackgroundStore.jobsAwaitingAvailabilityAnswer()` reconstructs the pending set from the verdicts already being written. `AvailabilityBacklog.seed(with:)` adopts them additively and de-duplicated, so a seed arriving mid-drain can't reorder or double work in flight. Oldest-checked first, so a resumed drain works on what has waited longest.

To make that decision robust, the stored detail for an unverified job is now the raw `UnverifiedReason` case rather than its sentence — resuming must not hinge on phrasing that could be reworded. `UnverifiedReason.displaySummary(for:)` resolves it back for the UI, and falls through for a gone reason (free text) or a row written before the change.

**#5** Re-seeding is gated on a 24h staleness interval held in the drain task. Without it a permanently unanswerable posting would be re-asked every five minutes forever; with it, drainage stops when clear and resumes daily. A relaunch is itself a fresh seed.

**#2** still holds — the drain calls `findGoneJobsRotating` directly and never writes `availability_last_auto_check_at`.

not verified: (visual) — the end-of-drain notification and its click-through to the confirmation sheet still need a live desktop and a drain long enough to complete; unchanged from the first pass.
<!-- SECTION:FINAL_SUMMARY:END -->
