---
id: TASK-636
title: 'Generalize authoritative ATS lookups beyond Greenhouse (Lever, Ashby, Workday)'
status: Done
assignee: []
created_date: '2026-07-22 23:20'
updated_date: '2026-08-09 23:54'
labels:
  - ats
  - availability
  - architecture
dependencies:
  - TASK-631
modified_files:
  - core/Services/ATSProvider.swift
  - core/Services/ATSProviders.swift
  - core/Services/JobService+ATS.swift
  - core/Services/BackgroundStore.swift
  - core/Services/AvailabilityChecker.swift
  - app/Views/Detail/JobDetailView.swift
  - tests/CoreTests/ATSProviderTests.swift
  - tests/CoreTests/GreenhouseJobBoardTests.swift
priority: low
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
TASK-631 uses the Greenhouse public Job Board API as an authoritative availability/metadata source. The same pattern generalizes to the other ATSes we already detect posting ids for: Lever (api.lever.co/v0/postings/{company}[/{id}]), Ashby (public posting API), and Workday (the CXS endpoint we already query for liveness). Introduce a small provider abstraction — "given an ATS id + company/host, return {alive, content, title, location, updated_at, questions}" — so availability, description-refresh (TASK-632), freshness (TASK-633), company-roles (TASK-634), and form-preview (TASK-635) all work across providers instead of Greenhouse-only. Keep it public-source / no-credential; each provider is best-effort with graceful fallback to today's HTML behavior.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 A provider protocol abstracts authoritative lookup (alive/content/metadata) keyed by ATS id + company/host
- [x] #2 Greenhouse (existing), Lever, and Ashby are implemented as providers; Workday liveness is folded in
- [x] #3 Availability + the metadata features consume the abstraction rather than Greenhouse-specific code
- [x] #4 Each provider is public/no-key, bounded by timeouts, and falls back cleanly
<!-- AC:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
#1 `ATSProvider` (protocol) + `ATSPosting` (normalized value) + `ATSRegistry` (routes an id from `DuplicateDetector.atsPostingID` to a provider). `ATSPosting` models the *union* of what vendors publish rather than a lowest common denominator, because they genuinely disagree: Lever has no update timestamp, Ashby's is frequently null, Greenhouse has both.

#2 Greenhouse (wrapping the existing client), Lever and Ashby implemented; Workday folded in as liveness-only. All three new endpoints were checked live before writing the decoders (api.lever.co/v0/postings/spotify — 103 roles; api.ashbyhq.com/posting-api/job-board/ramp — 122 roles). Two things that would have been silent bugs: **Lever stamps `createdAt` in milliseconds** (read as seconds, every posting dates to 1970 and the whole corpus looks stale), and **Lever's requirements live in `additionalPlain`**, so using `descriptionPlain` alone hands extraction a posting with no requirements. Ashby's `isListed == false` marks roles the employer hid from their own board, so those are omitted.

#3 `BackgroundStore.greenhouseIdentity`/`applyGreenhouseRefresh` became `atsIdentity`/`applyATSRefresh`; `JobService+Greenhouse.swift` became `JobService+ATS.swift` with `refreshFromATS`; `AvailabilityChecker`'s `JobSpec.greenhouseJobID` became `atsID` and the confirm-alive override now asks `provider.isAlive`. The job detail button reads "Refresh from Lever"/"Ashby"/"Greenhouse" from the provider's own name.

#4 All public, no keys, bounded timeouts (20s for board listings, which are large; 12s for single postings). The critical invariant is that `nil` and `false` stay distinct — "couldn't reach the board" must never read as "removed" or a transient outage mass-expires live jobs. Greenhouse keeps confirming the board resolves before trusting a 404; Lever and Ashby treat an *empty* board as indeterminate, since an empty list is also what a wrong company handle returns (two plausible-looking handles returned `[]` during development).

Workday is deliberately liveness-only: its CXS search settles whether a requisition exists but returns no description worth having, and a `fetchPosting` handing back a search-result summary would let the refresh overwrite a real capture with a stub.

15 tests. Gate: fast gate TEST SUCCEEDED, BUILD SUCCEEDED, swiftlint 0 violations in 339 files, swiftformat 0.61.1 clean.

not verified: no end-to-end refresh was run against a live Lever or Ashby job in the app — the decoders are tested against fixtures shaped from real responses, and the fetch/routing layer is compile-checked. The `RefreshError` cases are still named for Greenhouse (`notGreenhouse`) though their user-facing messages are now vendor-neutral; renaming them is cosmetic and was left alone.
<!-- SECTION:FINAL_SUMMARY:END -->
