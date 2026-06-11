---
id: TASK-156
title: >-
  LLM: Route all re-run extraction actions through a status-resetting service
  method
status: Done
assignee: []
created_date: '2026-06-11 19:32'
updated_date: '2026-06-11 21:22'
labels:
  - llm
  - workflow
  - ui
  - bug
dependencies: []
references:
  - app/Views/Jobs/JobsView.swift
  - app/ContentView.swift
  - core/Services/JobService.swift
  - core/LLM/QueueActor.swift
modified_files:
  - app/ContentView.swift
  - app/Views/Jobs/JobsView.swift
  - app/Views/Quality/DataQualityView.swift
  - tests/CoreTests/JobServiceTests.swift
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
LLM/extraction audit finding: some UI actions enqueue extraction directly without setting `Job.extractionStatus` back to pending or clearing stale errors. `JobService.resetExtraction` does this, but direct `QueueActor.enqueue(..., mode: .extract)` calls bypass it.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 All user-visible re-run extraction actions call a Core service path that resets extraction status/error/timestamps and enqueues consistently.
- [ ] #2 Jobs show a pending/running state immediately after re-run is requested rather than stale success/failure state.
- [ ] #3 Bulk re-run extraction uses the same service behavior as single-job reset.
- [ ] #4 Tests cover direct and bulk re-run status transitions.
<!-- AC:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Replaced all direct `queueActor.enqueue(..., mode: .extract)` and `enqueueLLM(..., mode: .extract)` re-run calls with `resetExtractionBulk(jobIDs:)` in ContentView, JobsView (3 sites), and DataQualityView. Tests cover single-job reset clearing stale fields and bulk reset creating one request per job.
<!-- SECTION:FINAL_SUMMARY:END -->
