---
id: TASK-444
title: 'Capture lookup: Match jobs by canonical and normalized URLs for open-in-app'
status: Done
assignee: []
created_date: '2026-06-13 18:54'
updated_date: '2026-06-15 18:37'
labels:
  - audit
  - ingestion
  - extension
  - ux
dependencies: []
references:
  - core/Services/JobService.swift
  - extension/service_worker.js
  - server/swift/JobhuntServer.swift
modified_files:
  - core/Services/URLNormalizer.swift
  - core/Services/JobService.swift
  - tests/CoreTests/JobServiceTests.swift
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
`JobService.findJobNumber(byURL:)` currently fetches all captures and returns the first capture whose original `url` exactly equals the requested URL. The extension's Open this job in Jobhunt action can fail when the current tab URL differs from the stored URL by canonical URL, tracking parameters, redirects, or other normalization differences.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Job lookup considers stored original URL, stored canonical URL, and a normalized URL representation where appropriate.
- [x] #2 Lookup avoids scanning all captures when the store can support a bounded query or indexed lookup.
- [x] #3 The extension Open this job in Jobhunt action succeeds for a captured page reached through a canonical or normalized equivalent URL.
- [x] #4 Add tests for exact URL, canonical URL, and normalized/tracking-parameter URL lookup behavior.
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Supersedes TASK-367 (2026-06-12), a perf-framed duplicate of the same JobService.findJobNumber(byURL:) all-capture in-memory scan. This task is the superset: AC#2 retains 367's indexed/bounded-lookup performance requirement, and it adds the canonical/normalized URL matching correctness work. 367 archived.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
findJobNumber(byURL:) now (1) does a bounded SwiftData predicate lookup matching the stored original url OR canonical url (AC#1/#2 — no all-capture scan in the common case), then (2) on a miss, compares normalized forms via the new shared URLNormalizer (drops fragment + tracking params utm_*/gclid/etc, sorts remaining query, strips trailing slash, lowercases scheme/host) so a tab reached via a canonical/tracking/trailing-slash equivalent still resolves (AC#1/#3). Tests cover exact-original, exact-canonical, tracking-param, and trailing-slash lookups, an unrelated-URL miss, and the normalizer's canonicalization (AC#4). URLNormalizer is the centralization seam for TASK-443. (Supersedes TASK-367.)
<!-- SECTION:FINAL_SUMMARY:END -->
