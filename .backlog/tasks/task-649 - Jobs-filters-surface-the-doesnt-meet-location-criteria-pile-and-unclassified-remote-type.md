---
id: TASK-649
title: >-
  Jobs filters: surface the "doesn't meet location criteria" pile and
  unclassified remote type
status: In Progress
assignee: []
created_date: '2026-07-26 19:36'
labels:
  - jobs
  - filters
  - triage
  - workflow
dependencies: []
references:
  - app/Views/Jobs/JobsFilterState.swift
  - app/Views/Jobs/JobsView.swift
  - core/LLM/LocationCriteria.swift
  - app/Views/Jobs/SaveSearchSheet.swift
priority: high
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
A remote-only job seeker triaging scraped captures needs to find in-office postings to review (and then archive by hand). The app already computes this correctly but gives no way to select it.

`LocationCriteria.meets` treats `unknown`/`nil` remote type as onsite when no preferred locations are configured ("unknown/none ≈ onsite"), so with `allow_onsite=false` those jobs are already stored with `meetsCriteria = false`. On the live store that's 20 of 81 New jobs — exactly the pile the user wants to review.

Two gaps, both in the filter UI, not the logic:

1. `JobsFilterState.meetsCriteriaOnly` is a Bool — it can only show jobs that DO meet. There is no way to select the complement.
2. The Remote filter offers only remote/hybrid/onsite (`ForEach([RemoteType.remote, .hybrid, .onsite])`). There's no Unknown toggle, so the ~120 unclassified jobs are unreachable. Note `job.remoteType` can also be nil, which must be treated as unknown for filtering.

Explicitly OUT of scope: any automatic archiving or bulk action driven by these filters. "Doesn't meet criteria" is a heuristic, not a fact — a posting that never states its arrangement may still be remote-friendly, and the user maintains a shortlist of companies they would go onsite for. These filters exist to support human review; archiving stays a deliberate user action.

Deliberately NOT changing the extractor to infer `onsite` from a bare city name: `LocationCriteria` already treats unknown as onsite for filtering, so the semantics are right, and emitting a confident `onsite` label would make the stored data claim something the posting never said.

Saved searches persist filter state, so any change must not break existing saved searches.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 The Meets-criteria filter is tri-state: Any / Meets / Doesn't meet
- [ ] #2 Selecting "Doesn't meet" lists exactly the jobs whose stored meetsCriteria is false
- [ ] #3 The Remote filter offers an Unknown option that also matches jobs whose remoteType is nil
- [ ] #4 Existing saved searches that encoded the old boolean meets-criteria filter still load and behave as before
- [ ] #5 Filter chips/Clear All reflect the new options, and the active-filter count stays correct
- [ ] #6 No automatic archiving or status change is introduced by these filters
- [ ] #7 Filter predicate logic is covered by unit tests, including the nil-remoteType case
<!-- AC:END -->
