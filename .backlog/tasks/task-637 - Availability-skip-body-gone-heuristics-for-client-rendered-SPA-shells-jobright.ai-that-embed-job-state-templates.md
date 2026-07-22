---
id: TASK-637
title: >-
  Availability: skip body-gone heuristics for client-rendered SPA shells
  (jobright.ai) that embed job-state templates
status: Done
assignee: []
created_date: '2026-07-22 23:29'
updated_date: '2026-07-22 23:30'
labels:
  - availability
  - detection
dependencies: []
priority: high
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
jobright.ai (and similar SPA aggregators) render the job client-side; their STATIC HTML shell embeds job-state UI templates — an expired-job apply button and a "…was closed" block — for EVERY job, live or not. The availability checker's bodyGoneReason then false-flags live jobs as gone (reported: https://jobright.ai/jobs/info/6a53a1f68a74e077472f90e2 is live but flagged expired). Same class as Cribl #325, but no gh_jid so the Greenhouse override (TASK-631) can't help.

Add a small registrable-host denylist (bodyUnreliableHosts) checked in checkURL after the authoritative status-code / board-landing checks and BEFORE the body heuristics: for such hosts return .unverifiable (never .gone) since a real removal there also just returns the 200 shell. Hard 404/410 and redirect signals still apply. Seed with jobright.ai; extend as new SPA shells surface.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 A jobright.ai job returning a 200 SPA shell containing 'expired'/'was closed' template markup is .unverifiable, not .gone
- [ ] #2 A real 404/410 on such a host is still .gone (status codes are authoritative)
- [ ] #3 The host match covers subdomains and www
- [ ] #4 Test covers the SPA-shell false-positive and the still-gone 404 case
<!-- AC:END -->
