---
id: TASK-308
title: 'LLM queue: Respect active-resume fit mirror rule on fit failures'
status: Done
assignee: []
created_date: '2026-06-12 19:34'
updated_date: '2026-06-12 19:47'
labels:
  - audit
  - llm-queue
  - fit-scoring
dependencies: []
references:
  - core/Services/BackgroundStore.swift
  - core/LLM/QueueActor.swift
modified_files:
  - core/LLM/QueueActor.swift
  - core/Services/BackgroundStore.swift
  - tests/CoreTests/JobServiceTests.swift
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

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Added active-resume guard to markFitScoreFailed in BackgroundStore.swift. The method now checks record.resume?.active == true before updating job.fitStatus, mirroring the guard already present in saveFitScore. The separate unconditional Job.self update block in QueueActor.swift (lines 627-633) was removed — job-level mirror updates for failure are now consolidated in markFitScoreFailed. Two tests added: testMarkFitScoreFailed_activeResume_updatesJobMirror and testMarkFitScoreFailed_inactiveResume_doesNotUpdateJobMirror.
<!-- SECTION:FINAL_SUMMARY:END -->
