---
id: TASK-510
title: >-
  Workflow: Mark ready-to-review jobs unread so Dock badge and list emphasis
  work
status: Done
assignee: []
created_date: '2026-06-19 01:30'
updated_date: '2026-06-19 02:17'
labels:
  - workflow
  - notifications
  - jobs
dependencies: []
references:
  - docs/workflow.md
  - app/ContentView.swift
  - app/Views/Jobs/JobsView.swift
  - core/LLM/QueueActor.swift
  - core/Services/JobService.swift
priority: high
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Finding: The workflow promises that the Dock badge shows the unread-job count (`docs/workflow.md` step 4), and the UI queries `Job.unread` in `ContentView` and styles unread rows in `JobsView`. Production code only clears `unread` in `JobService.markOpened` / `markRead`; no production path sets it true when AI processing makes a job ready to review.

Why this matters: Users can miss newly processed jobs because the badge and unread row emphasis never activate. The documented review loop depends on an attention cue after background extraction/fit work completes.

Suggested implementation: Set `Job.unread = true` when a job first becomes ready for review, likely in the queue success path after extraction and/or fit completion. Preserve existing behavior that selecting/opening the job clears `unread`. Avoid marking semantic duplicates unread if product policy says duplicates wait in the Duplicates view rather than normal review.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 A newly captured non-duplicate job is marked `unread == true` when it becomes ready for review after successful AI processing.
- [x] #2 Opening/selecting the job continues to clear `unread` through the existing `markOpened`/`markRead` behavior.
- [x] #3 The Dock badge count and Jobs list unread styling reflect the newly ready job without requiring an app restart.
- [x] #4 Semantic duplicate jobs are not marked unread by automatic extraction unless they are explicitly queued/unmarked for normal review.
- [x] #5 Focused tests cover the transition from processed job to unread and unread clearing on open/read.
<!-- AC:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Already implemented in commit 8e57b80 (predates this task being filed). QueueActor sets Job.unread = true atomically with the extracted fields on extraction success; markOpened/markRead still clear it on open. AC#1/#3 covered by testQueuePipeline_extractsJobViaMockServer (asserts unread true after extraction); AC#2/#5 by existing testMarkOpened_setsLastOpenedAndClearsUnread. AC#4 holds by construction — insertCaptureAtomically only queues extraction when duplicateOfJobID == nil, so semantic duplicates never auto-extract and are never marked unread. Dock badge (DockBadgeUpdater + unread @Query) and the docs were updated in the same commit.
<!-- SECTION:FINAL_SUMMARY:END -->
