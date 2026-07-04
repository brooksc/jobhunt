---
id: TASK-594
title: >-
  Availability: http:// job URLs never checked (ATS-blocked) + Greenhouse
  expired-posting detection
status: Done
assignee: []
created_date: '2026-07-04 02:47'
updated_date: '2026-07-04 02:47'
labels:
  - availability
  - expiration
  - bug
  - ats
dependencies: []
references:
  - core/Services/AvailabilityChecker.swift
  - core/Services/JobURLPolicy.swift
  - Project.swift
modified_files:
  - core/Services/AvailabilityChecker.swift
  - tests/CoreTests/AvailabilityCheckerTests.swift
priority: high
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Investigating job #37 (GitLab/Greenhouse, status pursuing) which is expired but never auto-flagged surfaced two stacked bugs in AvailabilityChecker:

1. PRIMARY — ATS blocks the request. Job #37's URL is plain `http://job-boards.greenhouse.io/gitlab/jobs/8509676002`. The app's ATS config (Project.swift) sets only NSAllowsLocalNetworking (no NSAllowsArbitraryLoads), so URLSession refuses the plain-HTTP external request (throws -1022) before following any redirect. checkURL catches that as `.error` → treated as available, so the posting is never actually fetched and never flagged gone. Scope: 10 of 50 jobs (20%) have http:// source URLs — all silently un-checkable.

2. SECONDARY — Greenhouse "posting gone" signal is subtle. An expired Greenhouse posting 302-redirects to the board root with `?error=true` (e.g. `…/gitlab?error=true`) at HTTP 200. Status isn't 404/410, the board body has no removal phrases, and `/gitlab` isn't in the redirect-suffix list, so most heuristics miss it (only the fragile redirect+missing-title heuristic happens to catch it).

Reference: `curl` of the URL shows `http 301 → https 302 /gitlab?error=true → 200`.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Availability check upgrades http:// request URLs to https:// so ATS no longer blocks them (redirect comparison uses the upgraded URL)
- [x] #2 Greenhouse `?error=true` board-root landing is detected as a deterministic gone signal
- [x] #3 Unit tests cover the http-URL Greenhouse-expired case end-to-end, the https-upgrade helper, and the board-error detector (no false positive on live postings or non-Greenhouse hosts)
- [x] #4 Full fast gate green
<!-- AC:END -->



## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Fixed both issues in AvailabilityChecker (commit follows).

- Added `httpsUpgraded(_:)` and applied it at the top of `checkURL`, using the upgraded URL as the request target AND the redirect-comparison baseline. This unblocks the ATS problem: every http:// job URL is now actually fetched (over https, which all job boards serve + 301 to anyway) instead of erroring to 'available'. Fixes ~20% of jobs that were silently un-checkable.
- Added `isBoardErrorLandingURL(_:)` (Greenhouse `error=true` on a greenhouse.io host) and a 1.5 check in `checkURL` returning `.gone(reason: 'board posting not found: …')`. Deterministic, can't false-positive on a live posting (no error query) or non-Greenhouse host.
- Tests: `testGreenhouseExpiredPosting_httpURL_isGone` (end-to-end: http input → asserts request upgraded to https → board?error=true landing → gone), `testHTTPSUpgrade_onlyRewritesPlainHTTP`, `testBoardErrorLanding_detectsGreenhouseErrorQueryOnly`. Full fast gate green (CoreTests/ServerTests/MCPTests).

Follow-ups noted (not done): (a) broaden redirect-to-non-job detection to same-host deep→shallow board-root redirects for other ATS (Lever/Ashby/Workday) — needs its own testing to avoid false positives; (b) consider a periodic re-check or manual 'Check availability' on job #37 to confirm it now flags in the live app.
<!-- SECTION:FINAL_SUMMARY:END -->
