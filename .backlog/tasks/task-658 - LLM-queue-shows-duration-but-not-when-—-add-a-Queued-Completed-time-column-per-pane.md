---
id: TASK-658
title: >-
  LLM queue shows duration but not when — add a Queued/Completed time column per
  pane
status: Done
assignee: []
created_date: '2026-08-02 18:09'
updated_date: '2026-08-09 22:33'
labels:
  - llm-queue
  - ui
dependencies: []
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
`LLMQueueView` has a **Duration** column (`durationString`, `LLMQueueView.swift:431`) but no absolute timestamp anywhere, so the queue can't answer the two questions it's actually consulted for:

- **Active pane:** how long has this been sitting here? Duration is measured from `startedAt`, so a request that is `queued` and never started shows `—`. A job queued 40 minutes ago is indistinguishable from one queued 40 seconds ago.
- **Completed pane:** is everything in here stale, i.e. safe to clear? There's no way to tell yesterday's rows from this batch, so "Clear Finished Requests" is a leap of faith.

**Wanted:** one timestamp column whose meaning follows the pane (`LLMQueueView.swift:125`/`131`):

| Pane | Column | Source |
|---|---|---|
| Active | "Queued" | `createdAt` |
| Completed | "Completed" | `finishedAt` |

One column, not both — each pane only needs the one relevant to it.

**Format:** time alone for today (`10:34`), date + time for anything older (`Jul 31 16:51`). Absolute, not relative — "12 minutes ago" re-renders constantly and reads worse when scanning a column for a batch boundary. Duration already covers elapsed time, so this is the complement, not a replacement.

Motivating case: the orphaned `running` row in [TASK-657] had been queued 12 minutes and running 11, but the view showed only a duration — nothing said *when*, so spotting it as abnormal meant querying the store by hand.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Active pane shows a Queued column sourced from createdAt
- [x] #2 Completed pane shows a Completed column sourced from finishedAt
- [x] #3 A timestamp from today renders as time only; older rows include the date
- [x] #4 A queued-but-not-started request shows its queued time (its Completed cell renders an em dash)
- [x] #5 The existing Duration column is unchanged
<!-- AC:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Each pane now shows the timestamp that means something for its rows: Active shows **Queued** from `createdAt`, Completed shows **Completed** from `finishedAt`. The shared `requestTable` takes a `TimeColumn` rather than gaining both columns everywhere — a Completed column in the Active pane would be an em dash on every row.

Same-day rows render time only; anything older carries its date. A column wide enough for a full date on every row would spend most of its width repeating today's date, and the date only starts carrying information once the row isn't from today.

The formatting rule lives in `QueueTimestamp` in Core rather than the view, so it can be tested with an injected clock and a fixed locale — app-target code has no unit-test target. Three tests: today is time-only, older includes the date, and nil renders as an em dash (the case a queued-but-unstarted request produces in the Completed column).

Duration is untouched, as criterion 5 requires.
<!-- SECTION:FINAL_SUMMARY:END -->
