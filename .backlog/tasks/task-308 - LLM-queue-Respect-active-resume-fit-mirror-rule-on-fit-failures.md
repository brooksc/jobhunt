---
id: TASK-308
title: 'LLM queue: Respect active-resume fit mirror rule on fit failures'
status: To Do
assignee: []
created_date: '2026-06-12 19:34'
labels:
  - audit
  - llm-queue
  - fit-scoring
dependencies: []
references:
  - core/Services/BackgroundStore.swift
  - core/LLM/QueueActor.swift
priority: high
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Successful fit scoring only updates Job.fitScore fields when the scored resume is active, but the retry-exhausted failure path writes Job.fitStatus = failed directly for any fit request. A failed inactive-resume score can make the job's active fit state look failed.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Fit failure handling updates job-level fit mirrors only when the failed request belongs to the active resume.
- [ ] #2 Inactive-resume failures update only the corresponding JobFitScore record.
- [ ] #3 Regression tests cover failed active and failed inactive resume scoring.
<!-- AC:END -->
