---
id: TASK-274
title: 'Fit scoring: Persist per-resume failure state'
status: To Do
assignee: []
created_date: '2026-06-12 03:33'
labels:
  - audit
  - fit-scoring
  - queue
  - ux
dependencies: []
references:
  - core/LLM/QueueActor.swift
  - core/Services/BackgroundStore.swift
  - core/Models/JobFitScore.swift
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Successful fit scoring creates or updates a JobFitScore record, but terminal failures only mark the denormalized Job fit status. Persist failed status and error context for the specific job/resume pair so the detail UI can show what failed and allow targeted retry.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 A fit request that exhausts retries creates or updates the corresponding JobFitScore with failed status.
- [ ] #2 Failure reason is available in diagnostics or UI for the job/resume pair.
- [ ] #3 Tests cover failed fit scoring for an existing resume and job.
<!-- AC:END -->
