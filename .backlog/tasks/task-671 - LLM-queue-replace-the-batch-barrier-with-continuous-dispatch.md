---
id: TASK-671
title: 'LLM queue: replace the batch barrier with continuous dispatch'
status: To Do
assignee: []
created_date: '2026-08-09 19:44'
labels:
  - llm-queue
  - performance
dependencies: []
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Split out of TASK-657, whose other nine criteria are done. This is the remaining half.

`QueueActor.startProcessing` fetches `limit` requests, dispatches them all into one `withTaskGroup`, and waits for **every** task before the next pass. So a single slow request holds the whole batch open: slots free up as siblings finish, but nothing new starts until the slowest one returns.

With the per-request deadline (`withRequestDeadline`, 1.5 × `llmTimeout`) and the orphan reaper both in place, this is no longer a wedge — it is a throughput cost. A batch of four where one request takes 140s and three take 16s runs at one-quarter utilisation for two minutes.

## What to do

Keep the group filled instead of draining it: as each outcome arrives, dispatch the next queued request if a slot is free, rather than waiting for the batch to empty.

Two things to be careful of, both load-bearing in the current code:

- **Auto-pause calls `group.cancelAll()`** after `autoPauseThreshold` consecutive provider failures, and must still stop the whole batch — a top-up loop must not immediately re-dispatch into a queue that has just been paused.
- **The adaptive concurrency limit changes mid-pass** (`adaptive?.onSuccess()` / `onFailure()`, and a 429 collapses it to 1). Continuous dispatch has to respect the *current* effective limit each time it considers topping up, not the value sampled when the pass began.

Also worth guarding: a row dispatched but not yet marked `running` in the store could be re-fetched by the top-up query. Track in-flight ids in the loop rather than relying on the status write having landed.

## Acceptance criteria are inherited

Criteria 8 and 12 from TASK-657:
- A slow request no longer blocks queued work: new requests start as soon as a slot frees, without waiting for the whole batch.
- Test: a task group containing one never-returning task does not prevent remaining queued requests from being dispatched.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 A slow request no longer blocks queued work: new requests start as soon as a slot frees, without waiting for the whole batch
- [ ] #2 Test: a task group containing one never-returning task does not prevent remaining queued requests from being dispatched
- [ ] #3 Auto-pause still stops the whole batch — a top-up cannot re-dispatch into a just-paused queue
- [ ] #4 Top-up respects the CURRENT adaptive concurrency limit, including a 429 collapse to 1 mid-pass
<!-- AC:END -->
