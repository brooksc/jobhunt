---
id: TASK-527
title: >-
  Queue lifecycle: reconcile JobFitScore state when running fit requests are
  cancelled, reset, or deleted
status: To Do
assignee: []
created_date: '2026-06-19 04:45'
labels:
  - audit
  - concurrency
  - queue
  - fit-score
  - data-integrity
dependencies: []
references:
  - core/LLM/QueueActor.swift
  - core/Services/BackgroundStore.swift
  - app/Views/Queue/LLMQueueView.swift
  - tests/CoreTests/ExtractionEngineTests.swift
  - tests/CoreTests/JobServiceTests.swift
priority: high
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Finding: queue actions update `LLMRequest` rows but do not consistently reconcile the paired `JobFitScore` record. A fit request can mark its score record `.running`; if the user cancels while the provider is in flight, the success path observes the request is no longer running and returns without resetting the `JobFitScore`. Similarly, queue reset/delete operations act on request rows without updating the fit-score mirror.

Why this matters: the request lifecycle and fit-score lifecycle can diverge. The queue may show a request cancelled/reset/deleted while the job still presents a fit score as running, pending, failed, or stale. That creates misleading UI state and can block reliable retry behavior.

Suggested implementation: make fit request state transitions update both the `LLMRequest` and the corresponding `JobFitScore`/job mirror atomically where the request has job and resume IDs. Define explicit outcomes for cancel, reset, delete, and retry: e.g. cancel clears running state or marks cancelled-equivalent fit state, reset moves the score record to pending and clears stale output, delete recomputes the mirror without leaving an active-looking score.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Cancelling a running fit request does not leave the associated `JobFitScore.fitStatus == .running` indefinitely.
- [ ] #2 Resetting a fit request to queued updates the associated fit score record to the chosen queued/pending semantics and recomputes the job mirror.
- [ ] #3 Deleting a fit request does not leave job-level fit mirror state that implies active processing when no active fit request remains.
- [ ] #4 Extraction request cancellation behavior remains unchanged except where shared queue helpers require tests.
- [ ] #5 Focused tests cover cancel-running-fit, reset-fit-request, and delete-fit-request lifecycle reconciliation.
<!-- AC:END -->
