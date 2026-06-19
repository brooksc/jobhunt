---
id: TASK-520
title: >-
  State machine: fail fit score records when fit requests fail before provider
  execution
status: Done
assignee: []
created_date: '2026-06-19 02:00'
updated_date: '2026-06-19 05:07'
labels:
  - audit
  - state-machine
  - fit-score
  - llm
  - data-integrity
dependencies: []
references:
  - core/LLM/QueueActor.swift
  - core/Services/BackgroundStore.swift
  - core/Models/Enums.swift
  - tests/CoreTests/JobServiceTests.swift
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Finding: fit requests can fail before provider execution, such as when the referenced resume is missing or local LLM consent/configuration blocks the run. Those paths mark the `LLMRequest` failed, but they do not appear to mark the corresponding `JobFitScore` record failed. If a fit score record was already pending or running, it can remain stuck in a non-terminal state even though the request has failed.

Why this matters: request-level and fit-score-level state should tell the same lifecycle story. A stuck pending/running fit record can mislead the job mirror, keep UI indicators active, and make retries or failure diagnosis harder.

Suggested implementation: for pre-provider fit failures where both job and resume identifiers are available, call the same fit-record failure path used for provider failures and recompute the job-level mirror. Use a clear error message that distinguishes missing resume, consent/configuration, and provider failure.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 A fit request that fails because its resume is missing marks the corresponding fit score record failed when a record exists.
- [ ] #2 A fit request blocked before provider execution by local LLM consent/configuration records a terminal fit failure when job and resume identifiers are available.
- [ ] #3 The associated job-level fit mirror is recomputed after pre-provider fit failures.
- [ ] #4 Retry behavior remains explicit: failed records can be requeued by the existing retry/rescore flow without leaving duplicate active state.
- [ ] #5 Focused tests cover missing-resume and consent/configuration pre-provider failures.
<!-- AC:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
processFitRequest's pre-provider failure guards (empty/missing resume text, consent revoked) now call markFitScoreFailed so the JobFitScore moves off .pending instead of leaving the job's fit mirror stuck pending. The missing-job and missing-id guards remain markRequestCancelled (job deleted → fit scores cascade; malformed request). Commit cc71925.
<!-- SECTION:FINAL_SUMMARY:END -->
