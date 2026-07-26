---
id: TASK-649
title: >-
  Jobs filters: surface the "doesn't meet location criteria" pile and
  unclassified remote type
status: Done
assignee: []
created_date: '2026-07-26 19:36'
updated_date: '2026-07-26 20:25'
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
modified_files:
  - core/Services/JobFilterRules.swift
  - app/Views/Jobs/JobsFilterState.swift
  - app/Views/Jobs/JobsView.swift
  - tests/CoreTests/JobFilterRulesTests.swift
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
- [x] #1 The Meets-criteria filter is tri-state: Any / Meets / Doesn't meet
- [x] #2 Selecting "Doesn't meet" lists exactly the jobs whose stored meetsCriteria is false
- [x] #3 The Remote filter offers an Unknown option that also matches jobs whose remoteType is nil
- [x] #4 Existing saved searches that encoded the old boolean meets-criteria filter still load and behave as before
- [x] #5 Filter chips/Clear All reflect the new options, and the active-filter count stays correct
- [x] #6 No automatic archiving or status change is introduced by these filters
- [x] #7 Filter predicate logic is covered by unit tests, including the nil-remoteType case
<!-- AC:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Shipped across four commits. All filter rules live in `JobFilterRules` (JobhuntCore) so they're unit-testable — the app's filter closure isn't reachable from any test target. 21 tests.

**Location criteria — four buckets, not a boolean.** Job 443 (Delinea) exposed the flaw mid-implementation: extraction succeeded but the posting states no location or arrangement, and `LocationCriteria` scores unknown as onsite, so it was stored `false` and labelled a rejection. On the live store the label was wrong for *every* case — all 20 New jobs under "doesn't meet" were silent postings, and there were zero explicit onsite/hybrid New jobs. Split into `meets` / `notStated` / `doesNotMeet`, derived at filter time from `remoteType`, so no schema change or re-extraction was needed. Jobs whose verdict was never computed belong to no bucket (reachable via Extraction → Failed).

**Remote filter** gained Unknown, and `nil` remote type now counts as unknown — previously a job with no stored value matched *no* remote filter at all, leaving ~40 jobs unreachable.

**Data quality** filter (Any issue / High severity) reusing `QualityChecker`. Evaluated only when active: it faults each job's Capture when the byte caches are absent (131 of 547), which is the per-keystroke cost TASK-610 removed from search.

**Source, unread, never-scored** (added after reviewing the data): capture-host multi-select with counts — the host was previously reachable only via `displayCompany`'s fallback, so the 100 LinkedIn jobs *with* a company were unfindable by source; unread (186 of 547); and never-fit-scored (83), which `minFitScore` could not express because an absent score compares as 0 and fails every threshold.

Three of these were the same **nil-is-unreachable** bug class: nil remote type, uncomputed criteria verdict, absent fit score.

No automation was added — these filters support human review; archiving stays an explicit user action, since "doesn't meet" is a heuristic and the user keeps a shortlist of companies worth going onsite for.

`meetsCriteria`, quality, source, unread and unscored are all session-only, so no SavedSearch compatibility concerns; `minFitScore` (which *is* persisted) was deliberately left untouched.

Follow-up filed: TASK-650 (seniority is 55 distinct free-text values and is polluting fit scoring — must be normalized before a seniority filter is meaningful).
<!-- SECTION:FINAL_SUMMARY:END -->
