---
id: TASK-658
title: >-
  LLM queue shows duration but not when — add a Queued/Completed time column per
  pane
status: To Do
assignee: []
created_date: '2026-08-02 18:09'
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
- [ ] #1 Active pane shows a Queued column sourced from createdAt
- [ ] #2 Completed pane shows a Completed column sourced from finishedAt
- [ ] #3 A timestamp from today renders as time only; older rows include the date
- [ ] #4 A queued-but-not-started request shows its queued time (today Duration shows an em dash)
- [ ] #5 The existing Duration column is unchanged
<!-- AC:END -->
