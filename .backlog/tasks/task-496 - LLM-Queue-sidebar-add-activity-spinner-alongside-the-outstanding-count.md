---
id: TASK-496
title: 'LLM Queue sidebar: add activity spinner alongside the outstanding count'
status: Done
assignee: []
created_date: '2026-06-18 21:32'
updated_date: '2026-06-18 21:32'
labels:
  - ux
  - queue
dependencies: []
priority: low
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
The outstanding-count badge on the LLM Queue sidebar row is accurate but phased/jumpy: reprocessing a job creates 1 extract request first, then (only after extraction completes) the N fit requests, so the count shows 1 during extraction before jumping to N. Users read the small "1" as "nothing's happening".

Option C: keep the count badge (queued + running) AND add a small activity spinner on the row while the queue is actively processing (running > 0), so "it's working" is obvious regardless of the phased count.

Files: app/Shell/Sidebar.swift.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 LLM Queue sidebar row shows a spinner while any request is running
- [x] #2 The outstanding-count badge (queued + running) is retained and updates live
- [x] #3 Spinner disappears when nothing is running; badge hidden at zero
<!-- AC:END -->



## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Added an inline activity spinner to the LLM Queue sidebar row (shown while llmRunningCount > 0, derived from the existing non-terminal @Query), kept alongside the outstanding-count badge (queued + running). Now the row clearly signals active processing even when the count is small or briefly between the extract→fit phases. Build-verified. Note: the count itself comes from a SwiftData @Query that updates from the background processing context (the same mechanism the LLM Queue screen uses), so it should jump to N when the fits are enqueued; if it ever appears to lag during very fast churn, the follow-up would be to feed the sidebar from the queue event stream.
<!-- SECTION:FINAL_SUMMARY:END -->
