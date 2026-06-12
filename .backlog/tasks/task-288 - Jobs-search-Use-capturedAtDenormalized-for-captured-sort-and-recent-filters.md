---
id: TASK-288
title: 'Jobs search: Use capturedAtDenormalized for captured sort and recent filters'
status: Done
assignee: []
created_date: '2026-06-12 03:44'
updated_date: '2026-06-12 04:46'
labels:
  - audit
  - search
  - sorting
  - data-model
dependencies: []
references:
  - app/Views/Jobs/JobsView.swift
  - app/Views/Jobs/JobsSortLogic.swift
  - core/Models/Job.swift
modified_files:
  - app/Views/Jobs/JobsSortLogic.swift
  - app/Views/Jobs/JobsView.swift
  - core/Models/SavedSearch.swift
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
JobsView captured-date sort and recent filters use job.createdAt even though Job has capturedAtDenormalized for actual capture time. Use capturedAtDenormalized with createdAt fallback so imported or migrated jobs sort/filter by real capture date.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Captured-date sort uses capturedAtDenormalized when present and createdAt only as fallback.
- [x] #2 Recent-day filters use the same captured-date source as sort.
- [x] #3 Tests cover jobs where createdAt and capturedAtDenormalized differ.
<!-- AC:END -->
