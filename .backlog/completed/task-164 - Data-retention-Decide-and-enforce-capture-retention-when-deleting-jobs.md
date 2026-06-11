---
id: TASK-164
title: 'Data retention: Decide and enforce capture retention when deleting jobs'
status: Done
assignee: []
created_date: '2026-06-11 20:57'
updated_date: '2026-06-11 21:39'
labels:
  - audit
  - data-integrity
  - privacy
  - retention
dependencies: []
references:
  - core/Models/Capture.swift
  - core/Models/Job.swift
  - core/Services/JobService.swift
  - app/Views/Jobs/JobsView.swift
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Job-related child records cascade on delete, but `Capture.job` uses a `.nullify` relationship and `Job.capture` has no explicit cascade. The delete confirmation says deleting a job removes all related data, while raw capture content may remain orphaned. Decide whether captures are retained source records or deleted with jobs, then update delete rules, purge logic, UI copy, and tests accordingly.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 The product has an explicit policy for retaining or deleting raw captures after job deletion.
- [ ] #2 UI copy matches the implemented retention behavior.
- [ ] #3 Tests verify the chosen delete behavior for Job, Capture, and cascading child records.
<!-- AC:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Policy decision: delete Capture with Job (matches UI copy "all related data"). Added `@Relationship(deleteRule: .cascade)` to `Job.capture` in Job.swift. Previously `Job.capture` had no annotation (defaulted to `.nullify`), which left captures orphaned after job deletion. `Capture.job` retains `.nullify` to handle the unusual path of a standalone Capture deletion. Added `testDelete_jobDeleteCascadesToCapture` in JobServiceTests to verify the cascade. No schema migration needed (deleteRule change is not a stored-property rename/type-change).
<!-- SECTION:FINAL_SUMMARY:END -->
