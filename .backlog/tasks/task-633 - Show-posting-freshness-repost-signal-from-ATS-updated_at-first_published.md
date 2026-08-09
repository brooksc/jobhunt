---
id: TASK-633
title: Show posting freshness / repost signal from ATS updated_at + first_published
status: Done
assignee: []
created_date: '2026-07-22 23:20'
updated_date: '2026-08-09 23:29'
labels:
  - greenhouse
  - job-detail
  - signal
dependencies:
  - TASK-631
modified_files:
  - core/Services/PostingFreshness.swift
  - core/Services/GreenhouseJobBoard.swift
  - core/Services/BackgroundStore.swift
  - core/Models/Job.swift
  - app/Views/Detail/JobDetailView.swift
  - tests/CoreTests/PostingFreshnessTests.swift
  - tests/CoreTests/GreenhouseJobBoardTests.swift
priority: low
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
The Greenhouse Job Board API (and Lever/Ashby equivalents) expose `updated_at` and `first_published` for a posting. Surface a freshness signal on the job — e.g. "posted 2 days ago", "reposted", "stale 6 weeks" — so the user can triage by how fresh/active a listing is. Derive from the authoritative ATS timestamp when a gh_jid (or other ATS id) is available; otherwise fall back to our capture date. Read-only; no writes to the posting.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 A gh_jid job shows an authoritative posted/updated date from the ATS API
- [x] #2 A meaningful freshness label (fresh / stale / reposted) is derived and shown on the job
- [x] #3 Falls back to capture date when no ATS timestamp is available
<!-- AC:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
`PostingFreshness.make(firstPublished:atsUpdated:capturedAt:)` in Core produces the label, a level (fresh/recent/aging/stale) and a confidence; the job detail header shows it next to the capture date.

#1 `Job` gains `atsFirstPublishedAt` / `atsUpdatedAt`, written by the TASK-632 Greenhouse refresh (the API returns both — verified live). Two optional Date properties, which `Schema.swift`'s policy classes as a non-breaking addition: no version bump, and the V1 tripwire tests still pass.

#2 `first_published` is preferred over `updated_at` — the latter moves whenever the employer edits a typo, which would make an ancient requisition read as new. A gap of ≥14 days between the two is flagged as "updated since", the shape of a repost or a long-running requisition. Stale is 42 days, matching the task's own "stale 6 weeks" example.

#3 With no ATS date the label still appears but reads "Captured", not "Posted". This distinction is the one judgement call worth flagging: presenting our capture date as a posting date would be wrong in the single direction that matters, since it always makes a posting look newer than it is. The tooltip says which source the label came from.

**Design decision worth recording:** the ATS timestamps are only populated when the user runs the per-job "Refresh from Greenhouse" action. Fetching on view load would mean a network call per job rendered, and a background sweep would run the board-slug guess unattended across the corpus — the same reason TASK-632 kept the refresh explicit. So #1 is satisfied *after a refresh*; before one, the job falls back to #3.

10 tests. Gate: fast gate TEST SUCCEEDED, BUILD SUCCEEDED, swiftlint 0 violations in 330 files, swiftformat 0.61.1 clean.

not verified: (visual) — the label's appearance in the detail header.
<!-- SECTION:FINAL_SUMMARY:END -->
