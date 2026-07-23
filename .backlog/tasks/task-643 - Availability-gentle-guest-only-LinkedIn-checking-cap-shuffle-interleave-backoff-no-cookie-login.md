---
id: TASK-643
title: >-
  Availability: gentle guest-only LinkedIn checking (cap + shuffle + interleave
  + backoff); no cookie/login
status: Done
assignee: []
created_date: '2026-07-23 03:29'
labels:
  - availability
  - linkedin
dependencies: []
priority: high
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Decision: do NOT sign the user into LinkedIn via webview and reuse their session cookie for availability checks. It would not raise LinkedIn's (volume-based) rate limit and it risks getting the user's real LinkedIn account restricted/banned (automated access with their session violates LinkedIn's User Agreement) — an unacceptable trade mid-job-search. Stay guest-only (unauthenticated → nothing tied to the user to ban).

Instead make guest checking gentle so it's reliable and account-safe: (1) cap LinkedIn checks per run (maxLinkedInPerRun=12) + shuffle so a run can't fire a bursty volume; coverage rotates across runs (eventual, not per-run). (2) Interleave the paced LinkedIn pass with the concurrent non-LinkedIn pass (async let + actor-backed progress counter) so LinkedIn requests are spread across the run. (3) Back off on throttle — linkedInOutcome returns .throttled for 429/999/network error, and the paced pass stops checking LinkedIn for the rest of the run rather than hammering. A throttled check never false-expires.

Follow-ups if per-run probabilistic coverage proves insufficient: persist a per-job last-availability-checked timestamp for deterministic least-recently-checked rotation; and/or resolve LinkedIn postings to their underlying ATS (Greenhouse/Lever/Workday) which we check reliably.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 No LinkedIn login/cookie is used; checks remain guest-only
- [ ] #2 LinkedIn checks are capped per run and shuffled so coverage rotates across runs
- [ ] #3 The LinkedIn pass is interleaved with the concurrent pass and paced
- [ ] #4 A throttle/block (429/999/network error) backs off (stops the LinkedIn pass) and never marks a job expired
- [ ] #5 Tests cover the throttle-never-expires guarantee
<!-- AC:END -->
