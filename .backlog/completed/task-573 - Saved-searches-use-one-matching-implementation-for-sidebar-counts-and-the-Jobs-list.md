---
id: TASK-573
title: >-
  Saved searches: use one matching implementation for sidebar counts and the
  Jobs list
status: Done
assignee: []
created_date: '2026-06-20 05:12'
updated_date: '2026-06-26 02:01'
labels:
  - audit
  - saved-searches
  - jobs
  - filters
dependencies: []
modified_files:
  - core/Models/SavedSearchCriteria.swift
  - core/Models/SavedSearch.swift
  - app/Views/Jobs/JobsView.swift
  - app/Shell/Sidebar.swift
  - tests/CoreTests/SavedSearchTests.swift
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Finding: `Sidebar.refreshBadgeCounts` computes saved-search counts with `SavedSearchCriteria.matches`, while `JobsView.computeFilteredJobs` manually reimplements filtering. The two implementations already differ: live list text search includes `job.displayCompany`, `job.displayTitle`, and `capture.cleanedDescription`, while `SavedSearchCriteria` only checks raw company/title/location/job number. Live list number matching also treats plain numbers as exact-or-substring, while saved-search criteria uses substring only. This regresses the intent captured by prior TASK-286/TASK-364 comments that counts and job lists should share semantics.

Why it matters: A saved search can show a sidebar badge count that does not match the number of rows users see when they open it, especially for unextracted captures found via display title/host or searches that match cleaned job text. That undermines trust in saved searches and makes future filter additions risky because every new predicate must be added to multiple places.

Suggested implementation: Promote the live Jobs list filtering semantics into a reusable pure matcher, for example `JobListCriteria` plus a `JobListMatchFields` snapshot that includes display title/company and any searchable capture text needed for saved-search text matching. Have `JobsView.computeFilteredJobs`, `SavedSearch.matches`, and `Sidebar.refreshBadgeCounts` all call that matcher. Keep session-only filters explicitly outside `SavedSearchCriteria` or model them as optional criteria so the boundary is obvious.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Saved-search sidebar badge counts and opened saved-search row counts are computed from the same matcher.
- [x] #2 Text search behavior is identical for saved searches and the live Jobs list, including display title/company fallbacks and cleaned description matching where intended.
- [x] #3 Job-number matching rules are identical between saved searches and live search.
- [x] #4 Tests cover a saved search whose match depends on display title/host fallback or cleaned description, and assert count/list matcher parity.
<!-- AC:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Introduced SavedSearchCriteria.textNumberMatch — the single text/number matcher now called by both SavedSearchCriteria.matches (sidebar badge counts) and JobsView.computeFilteredJobs (live list). JobMatchFields was extended to snapshot displayCompany/displayTitle + cleanedDescription (built on the main actor in refreshBadgeCounts) so the count path consults exactly the fields the live list does: display title/company fallbacks (un-extracted jobs findable by page title/host) and cleaned description. Number matching is substring with `#` prefix stripped on both. Session-only filters (search tokens, advanced filterState, extraction/meetsCriteria) remain outside SavedSearchCriteria. Tests: SavedSearchCriteriaTests.testSharedTextNumberMatcher (display/location/desc/number/empty) and testSavedSearchCountUsesCaptureFallbacksAndCleanedDescription (count path matches by page title, host, cleaned description). Full CoreTests (916) green; lint clean.
<!-- SECTION:FINAL_SUMMARY:END -->
