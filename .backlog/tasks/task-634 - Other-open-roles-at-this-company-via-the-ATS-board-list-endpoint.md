---
id: TASK-634
title: '"Other open roles at this company" via the ATS board list endpoint'
status: Done
assignee: []
created_date: '2026-07-22 23:20'
updated_date: '2026-08-09 23:37'
labels:
  - greenhouse
  - discovery
  - job-detail
dependencies:
  - TASK-631
modified_files:
  - core/Services/GreenhouseJobBoard.swift
  - core/Services/OpenRoleRelevance.swift
  - core/Services/JobService+Greenhouse.swift
  - app/Views/Detail/OpenRolesSheet.swift
  - app/Views/Detail/JobDetailView.swift
  - tests/CoreTests/OpenRoleRelevanceTests.swift
priority: low
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
The Greenhouse board list endpoint (GET /v1/boards/{board}/jobs, no key) returns every open posting for a company. On a job whose company uses Greenhouse (board derivable via TASK-631), offer "other open roles at {company}" — list current postings, optionally filtered to similar titles/locations, with one-click add to the New funnel. A lightweight precursor to full discovery (DRAFT-001) scoped to a single already-known company. Lever/Ashby have analogous list endpoints.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 On a gh_jid job, the app can list the company's other current open roles from the ATS board API
- [x] #2 Results can be filtered (e.g. similar title/location) and added to New with source provenance
- [x] #3 Respects existing URL/duplicate-resolution policy so re-adds don't create dupes
- [x] #4 No credentials required; bounded timeouts + rate limiting
<!-- AC:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
`GreenhouseJobBoard.listOpenRoles(board:)` + `OpenRoleRelevance.rank(...)` in Core; `JobService.openRolesAtSameCompany(jobID:)` ties them together; `OpenRolesSheet` opens from an "Other roles here" button that only appears on gh_jid jobs.

#1 Live-verified: gitlab's board returned 189 open roles with the payload shape the decoder expects (nested `location`, numeric `id`, `first_published`). The board is resolved by fetching *this* posting first rather than guessing the slug a second time — listing another company's whole board would be a confusing failure and a silent one.

#2 189 unranked roles bury the two that matter, so results are ranked on shared title words and location with a "similar only" filter defaulting on. Similarity requires two shared words, or one plus a location match: a single shared word is usually "Engineer" and matches half the board. Location compares on the significant half so "Remote, Italy" matches "Italy" — exact equality would lose the signal on every remote posting. Ties break on title so the list doesn't reshuffle between openings.

#3 Adding goes through `addJobByURL`, which already applies the duplicate policy; the toast reports "Already tracked as #N" rather than pretending a new job was created.

#4 No credentials (public endpoint), 20s bounded timeout for the list (longer than the 12s single-posting timeout because the payload is large), and it's a per-job explicit action — one request when the user opens the sheet, so there's no sweep to rate-limit.

One deliberate UI decision: the empty state reads "Couldn't read the company's board, or it has no other open roles" because the service returns an empty list for both, and asserting the company has no other openings would be a claim we can't support.

12 tests. Gate: fast gate TEST SUCCEEDED, BUILD SUCCEEDED, swiftlint 0 violations in 333 files, swiftformat 0.61.1 clean.

not verified: (visual) — sheet layout and the add interaction. The list decode is verified against a real payload; the end-to-end sheet was not driven in a running app.
<!-- SECTION:FINAL_SUMMARY:END -->
