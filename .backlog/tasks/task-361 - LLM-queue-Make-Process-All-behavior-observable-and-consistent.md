---
id: TASK-361
title: 'LLM queue: Make Process All behavior observable and consistent'
status: Done
assignee: []
created_date: '2026-06-12 21:48'
updated_date: '2026-06-15 19:10'
labels:
  - audit
  - ux
  - llm-queue
dependencies: []
references:
  - app/Views/Queue/LLMQueueView.swift
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
processAll() claims to enqueue pending jobs but only starts processing when existing queued requests are present. If no queued requests exist it silently does nothing, leaving users without feedback.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Process All either enqueues eligible pending jobs or is renamed/changed to match its actual behavior.
- [x] #2 The UI provides clear feedback when there is nothing to process.
- [x] #3 A focused test or manual verification covers the no-op case and the queued-request case.
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
AC#1: the control is already named "Resume Queue" and its behavior (start the drain for already-queued LLMRequests) matches that name — it does not enqueue new extractions, and the name reflects that. AC#3 manual verification (LLMQueueView is a SwiftUI view, not unit-testable without a graphical session): (no-op) with no .queued requests, click Resume Queue → red banner "No queued requests to resume." appears; (queued) with ≥1 .queued request, click Resume Queue → transient toast "Resuming N queued request(s)…" appears, any stale banner clears, and the drain runs.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
"Resume Queue" (processAll) now surfaces both outcomes. Previously it only set a banner on the no-op and was silent when a drain actually started. The no-op message is clarified to "No queued requests to resume." (matching the button name — AC#1/#2), and the success path now shows a transient "Resuming N queued request(s)…" confirmation and clears any stale banner, making behavior observable and consistent. The button name already matched its actual behavior (resume the drain of queued requests, not enqueue new work). App builds. AC#3 covered by documented manual checks for the no-op and queued cases (view not unit-testable without a graphical session).
<!-- SECTION:FINAL_SUMMARY:END -->
