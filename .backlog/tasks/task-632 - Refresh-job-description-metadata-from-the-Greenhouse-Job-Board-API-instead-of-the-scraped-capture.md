---
id: TASK-632
title: >-
  Refresh job description + metadata from the Greenhouse Job Board API instead
  of the scraped capture
status: Done
assignee: []
created_date: '2026-07-22 23:20'
updated_date: '2026-08-09 23:22'
labels:
  - greenhouse
  - extraction
  - data-quality
dependencies:
  - TASK-631
modified_files:
  - core/Services/GreenhouseJobBoard.swift
  - core/Services/JobService+Greenhouse.swift
  - core/Services/BackgroundStore.swift
  - core/Services/AvailabilityChecker.swift
  - core/Services/JobService.swift
  - app/Views/Detail/JobDetailView.swift
  - tests/CoreTests/GreenhouseJobBoardTests.swift
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
For jobs carrying a Greenhouse gh_jid, the public Job Board API (boards-api.greenhouse.io/v1/boards/{board}/jobs/{gh_jid}, no key) returns clean, complete fields — full `content` (description HTML), `title`, `location.name`, `departments`, `offices`, `updated_at`, `absolute_url` — far more reliable than the Cloudflare/JS-shell career-site capture we currently scrape. Offer a "refresh from source" that pulls the canonical content and re-runs extraction/fit on a complete, clean description, and backfills structured location. Reuse the board-token derivation from TASK-631. Keep it explicit/opt-in per job (or a batch action) so it doesn't silently overwrite user edits.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 A gh_jid job can be refreshed from the Greenhouse API, replacing/augmenting the captured description with the canonical `content`
- [x] #2 Structured location and other clean fields (title, departments) are backfilled without clobbering manual overrides
- [x] #3 Extraction/fit can be re-run on the refreshed description
- [x] #4 Falls back gracefully when the board can't be resolved or the API is unreachable
<!-- AC:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
`GreenhouseJobBoard` fetches and decodes the posting (reusing TASK-631's `greenhouseBoardCandidates`, now public); `BackgroundStore.applyGreenhouseRefresh` writes it; `JobService.refreshFromGreenhouse` ties the two together and re-extracts; a "Refresh from Greenhouse" button appears in the job detail action row only for postings carrying a `gh_jid`.

#1 The capture's `cleanedDescription` is replaced with the API's `content`. `visibleText` is updated in step — `recleanAllCaptures` recomputes cleaned text from it, so leaving the old shell text there would silently undo the refresh (there's a test for exactly that).

#2 Title and location are backfilled through the same `manualFieldOverrideSet` check extraction uses, and skipped fields are *reported* in the toast: silently keeping the user's value is indistinguishable from the refresh not working. The description itself is deliberately not override-protected — it's a scrape, not user-authored text, and replacing it is the whole point.

#3 `resetExtraction` runs after a successful refresh, but only when the description actually changed; re-running the model over identical text spends money to reproduce the answer already on screen.

#4 Every failure is a soft `RefreshError` (`notGreenhouse` / `boardNotResolved` / `malformedResponse`) with a distinct message, and the existing capture is left untouched. A 200 that won't decode is reported separately from a 404 so nobody goes looking for the wrong problem. This is also why the action is explicit and per-job rather than a sweep: the board slug is a guess and can resolve to the wrong company's board.

One thing worth recording: the API's `content` is HTML that has *also* been HTML-escaped, so it needs two strip passes. One pass only unescapes it, leaving literal `<p>` tags in the text handed to the model.

15 tests. Gate: fast gate TEST SUCCEEDED, BUILD SUCCEEDED, swiftlint 0 violations in 328 files, swiftformat 0.61.1 clean. `JobService.swift` crossed the file-length limit, so the new methods live in `JobService+Greenhouse.swift`.

not verified: no live call was made to boards-api.greenhouse.io from this environment, so the real payload shape is matched against Greenhouse's documented fields and the decode is tested against a fixture, not against production JSON. The button's appearance is also (visual) unverified.
<!-- SECTION:FINAL_SUMMARY:END -->
