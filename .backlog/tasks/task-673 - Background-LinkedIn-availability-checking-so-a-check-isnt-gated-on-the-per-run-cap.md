---
id: TASK-673
title: >-
  Background LinkedIn availability checking so a check isn't gated on the
  per-run cap
status: To Do
assignee: []
created_date: '2026-08-20 20:39'
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
- [ ] #1 The foreground check keeps the per-run LinkedIn cap and its pacing/backoff
- [ ] #2 LinkedIn postings outside a run's window are drained in the background without resetting the scheduled sweep's interval gate
- [ ] #3 A background 'gone' finding for an archived job surfaces somewhere the user will see it, without one notification per posting
- [ ] #4 The behaviour is opt-in or clearly disclosed, since it makes ongoing requests to LinkedIn from the user's IP
- [ ] #5 Drainage stops when the backlog is clear and resumes on a staleness interval rather than looping forever
<!-- AC:END -->
