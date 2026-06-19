---
id: TASK-516
title: >-
  State machine: show extraction as running while an extraction request is
  active
status: To Do
assignee: []
created_date: '2026-06-19 01:59'
labels:
  - audit
  - state-machine
  - llm
  - ui
dependencies: []
references:
  - core/LLM/QueueActor.swift
  - core/Models/Enums.swift
  - app/Views/Components/ExtractionChip.swift
  - app/Views/Detail/JobDetailView.swift
priority: high
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Finding: extraction requests transition `LLMRequest.status` to `running`, but the linked `Job.extractionStatus` appears to remain `pending` until final success or failure. UI already has a running state (`ExtractionChip` shows Extracting and `JobDetailView` disables the Run AI button only for `.running`), so the app can display a queued/pending job as if no extraction is actively running.

Why this matters: the job-level state is the user-facing lifecycle. If it does not mirror active queue work, users can get misleading progress indicators and may retry work that is already in flight. It also makes operational debugging harder because the request-level and job-level state machines disagree.

Suggested implementation: when an extract request is claimed for processing, update the linked job to `extractionStatus = .running` and clear any stale extraction error. Keep final success/failure transitions as the authority for terminal state. For retryable failures, decide whether the job should return to `pending` while waiting for the next attempt or remain `running` only during actual provider execution, and document/test that behavior.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 A job linked to an actively running extraction request has `Job.extractionStatus == .running` before provider work completes.
- [ ] #2 The extraction chip and Run AI button reflect the running state during active processing.
- [ ] #3 Final extraction success still sets `Job.extractionStatus == .succeeded` and clears stale extraction errors.
- [ ] #4 Final extraction failure still sets `Job.extractionStatus == .failed` and preserves the user-visible error.
- [ ] #5 Retryable extraction failures transition the job back to the chosen non-terminal waiting state consistently.
- [ ] #6 Focused tests cover request claim, success, failure, and retry/waiting behavior.
<!-- AC:END -->
