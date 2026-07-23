---
id: TASK-639
title: >-
  Availability: LinkedIn 404 is gone again (revert over-cautious unverifiable
  carve-out that missed removed jobs)
status: Done
assignee: []
created_date: '2026-07-23 02:07'
labels:
  - availability
  - detection
  - linkedin
dependencies: []
priority: high
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
TASK-626 made a LinkedIn /jobs/view 404 return .unverifiable (to protect a posting thought to be live-only-in-search, job #212). Investigation of all Interested LinkedIn jobs showed that was an over-correction: with the app's browser User-Agent, LinkedIn's guest /jobs/view returns a clean 404 for a genuinely removed posting (confirmed against LinkedIn's guest job API, jobs-guest/jobs/api/jobPosting/{id}, which 404s too) while live postings return 200. Job #212 is in fact removed now, and the carve-out was suppressing its (and every removed LinkedIn job's) detection — a false negative. Reverted: a LinkedIn 404 is gone again. Rate-limit/bot-block statuses (429/999) are not in goneStatusCodes, so they still fall through to .available (never false-expire).
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 A LinkedIn /jobs/view 404 resolves to .gone
- [ ] #2 A non-LinkedIn 404 still resolves to .gone
- [ ] #3 429/999 rate-limit/block responses do not resolve to .gone (fall through to available)
- [ ] #4 Test updated to assert LinkedIn 404 → gone
<!-- AC:END -->
