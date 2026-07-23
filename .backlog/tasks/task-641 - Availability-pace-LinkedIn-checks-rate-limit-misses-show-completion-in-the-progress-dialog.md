---
id: TASK-641
title: >-
  Availability: pace LinkedIn checks (rate-limit misses) + show completion in
  the progress dialog
status: Done
assignee: []
created_date: '2026-07-23 02:51'
labels:
  - availability
  - linkedin
  - ux
dependencies: []
priority: high
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Two issues surfaced after TASK-639/640. (1) Correctness: the bulk availability check fired ~35 LinkedIn URLs 10-at-a-time; LinkedIn throttles a burst (999/blocked/redirect), which the checker reads as 'available', so a genuinely-removed posting (#212, which 404s cleanly in isolation) was missed. findGoneJobs now partitions specs — non-LinkedIn stay fully concurrent (10), LinkedIn are checked SERIALLY with a 500ms pace so the burst can't trip the rate limit; a shared goneResult() helper preserves the Greenhouse confirm-alive override on both paths. (2) UX: the modal progress dialog now shows a 'nothing found' completion message with a Done button (instead of dismissing and flashing a transient toast) for both the availability check and the duplicate scan.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 LinkedIn availability checks run serially with a pace delay; non-LinkedIn stay concurrent
- [ ] #2 A removed LinkedIn posting (404) is caught rather than missed under bulk load (test)
- [ ] #3 The Greenhouse confirm-alive override still applies on both the concurrent and paced paths
- [ ] #4 The progress dialog shows a 'nothing found' completion with Done instead of a transient toast, for availability + duplicate scans
<!-- AC:END -->
