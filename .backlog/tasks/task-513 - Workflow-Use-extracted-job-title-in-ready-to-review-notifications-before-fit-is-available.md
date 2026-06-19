---
id: TASK-513
title: >-
  Workflow: Use extracted job title in ready-to-review notifications before fit
  is available
status: To Do
assignee: []
created_date: '2026-06-19 01:31'
labels:
  - workflow
  - notifications
  - llm
dependencies: []
references:
  - core/LLM/QueueActor.swift
  - app/Platform/PlatformIntegration.swift
  - docs/workflow.md
  - tests/CoreTests/ExtractionEngineTests.swift
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Finding: `QueueActor.processExtractRequest` updates `Job.title` from the extraction result, but then emits `.jobReady(jobNumber:title:fitScore:)` using `item.jobTitle`, a queued snapshot captured before extraction ran. If there is no active resume, or if fit scoring fails before emitting its own ready event, `PlatformIntegration` can notify with a generic "Job" body even though extraction found the real title.

Why this matters: Ready-to-review notifications are the user's entry point back into the workflow. Generic notification text makes it harder to decide what to review and weakens the value of background processing.

Suggested implementation: Emit the extracted title from `ExtractionResult` (or fetch/snapshot the updated job title after persistence) for the extraction ready event. Keep the later fit ready event able to update the same pending notification entry with a fit score and title. Add coverage for the no-active-resume path where only the extraction ready event is emitted.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 After successful extraction, the ready event includes the extracted title when one was returned by the model.
- [ ] #2 A job with no active resume produces a ready notification/body that uses the extracted title instead of generic "Job" when available.
- [ ] #3 When fit scoring later succeeds, the accumulated notification still includes the fit score and does not produce duplicate notifications for the same job in one processing drain.
- [ ] #4 If extraction returns no title, existing fallback behavior remains sensible.
- [ ] #5 Focused tests cover the extraction-only notification/event data path.
<!-- AC:END -->
