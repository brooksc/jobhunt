---
id: TASK-164
title: 'Data retention: Decide and enforce capture retention when deleting jobs'
status: To Do
assignee: []
created_date: '2026-06-11 20:57'
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
