---
id: TASK-629
title: >-
  Dedup: flag two captures of the identical full posting URL as a definitive
  duplicate
status: Done
assignee: []
created_date: '2026-07-22 22:16'
labels:
  - duplicates
  - detection
dependencies: []
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Two captures of the byte-identical full posting URL (query included) were only surfaced by the fuzzy domain-heuristic path (e.g. 80%) instead of as a definitive duplicate, because JobSnapshot.sourceURL uses the canonical (query-stripped) URL, which on SPA/aggregator sites (levels.fyi) is a generic category page shared by many jobs. Real case: Reddit jobs #15/#16 — same levels.fyi URL incl. jobId, captured 33s apart; the SPA rendered slightly different DOM so their cleanedHash differed, dodging the exact-hash path.

Add a same-full-URL detection path: group by a normalized full-URL key (host lowercased, query sorted, fragment/trailing-slash stripped) and pair matches as definitive (confidence 1.0, kind .sameURL). Gate on the URL carrying a query string so query-less generic category/SPA pages don't collapse unrelated jobs; query-less per-posting URLs (Greenhouse /jobs/N, LinkedIn /jobs/view/N) are already covered by the ATS-posting-id path.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Two captures of the identical full URL (query incl.) pair as a definitive duplicate (confidence 1.0, kind sameURL), ranked above the fuzzy path
- [ ] #2 The key requires a query string; query-less generic URLs do not trigger the same-URL path
- [ ] #3 Different query id (e.g. jobId) yields different keys and no same-URL pair
- [ ] #4 Focused tests cover match, query-less non-match, and differing-id non-match
<!-- AC:END -->
