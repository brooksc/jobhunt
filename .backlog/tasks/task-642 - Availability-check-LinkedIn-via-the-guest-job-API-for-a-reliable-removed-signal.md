---
id: TASK-642
title: >-
  Availability: check LinkedIn via the guest job API for a reliable removed
  signal
status: Done
assignee: []
created_date: '2026-07-23 03:07'
labels:
  - availability
  - linkedin
dependencies: []
priority: high
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Even with serial pacing (TASK-641), LinkedIn's auth-walled guest /jobs/view is unreliable for detecting removals under load: a removed posting's 404 gets throttled or redirected and reads as available, so #212 kept slipping through while closed-listing cases (#224/#225, caught via page body) were flagged. LinkedIn's guest job API (jobs-guest/jobs/api/jobPosting/{id}) is much lighter and gives a clean signal. findGoneJobs now routes LinkedIn specs through it: 404/410 = removed → gone; a 200 posting is live unless its body carries the closed banner or a gone phrase; a throttle/block (429/999) or network error can't confirm removal → not gone (never false-expires). Still checked serially with the existing pace to avoid tripping the limit. Note: could not validate end-to-end against real LinkedIn because it rate-limited the dev IP during diagnostics; the guest-API 404 signal was verified for #212 earlier and the paths are unit-tested.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 LinkedIn availability is checked via the guest job API (jobPosting/{id}) rather than /jobs/view
- [ ] #2 Guest API 404/410 → gone; 200 with closed/gone body → gone; 200 live → not gone; 429/999/error → not gone
- [ ] #3 LinkedIn job id is extracted from currentJobId search URLs and /jobs/view/{id} URLs
- [ ] #4 Focused tests cover 404, 200-closed, 200-live, and id extraction
<!-- AC:END -->
