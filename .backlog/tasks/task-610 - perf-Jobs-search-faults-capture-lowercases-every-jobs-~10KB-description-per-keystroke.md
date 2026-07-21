---
id: TASK-610
title: >-
  perf: Jobs search faults capture + lowercases every job's ~10KB description
  per keystroke
status: To Do
assignee: []
created_date: '2026-07-21 23:46'
labels:
  - performance
  - jobs
  - tech-debt
dependencies: []
priority: high
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
`JobsView.computeFilteredJobs()` (`JobsView.swift:722`) iterates all jobs and, for text search, calls `SavedSearchCriteria.textNumberMatch(... cleanedDescription: job.capture?.cleanedDescription ...)` which does `cleanedDescription?.lowercased().contains(q)` (`SavedSearchCriteria.swift:113`). This faults each job's SwiftData Capture row and allocates a full ~10 KB `.lowercased()` copy per job — for every job, every render. `searchText` is @State bound to `.searchable`, so body re-renders on every keystroke, and `filteredJobs` (a computed var) is evaluated multiple times per body (List + count + isEmpty + filteredIDs), so the O(N × 10 KB) pass runs several times per keystroke. Same class as the sidebar/Keychain-in-body bugs already fixed. At 285 jobs this is a real typing-lag source.

Fix options (do carefully): debounce searchText before filtering; and/or compute `filteredJobs` once per body (cache in @State recomputed via .onChange of searchText/filterState/sort/allJobs) instead of 4× per render; and/or precompute a lowercased searchable blob per job. Preserve exact match semantics (title/company/host/cleaned-desc/jobNumber).
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Typing in the Jobs search no longer faults+lowercases every job's description multiple times per keystroke
- [ ] #2 filteredJobs is computed at most once per render
- [ ] #3 Search match semantics unchanged (verified by SavedSearch/Jobs tests)
<!-- AC:END -->
