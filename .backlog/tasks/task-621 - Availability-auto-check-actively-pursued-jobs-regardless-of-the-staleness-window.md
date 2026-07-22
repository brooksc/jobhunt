---
id: TASK-621
title: >-
  Availability: auto-check actively-pursued jobs regardless of the staleness
  window
status: Done
assignee: []
created_date: '2026-07-22 20:19'
updated_date: '2026-07-22 20:20'
labels: []
dependencies: []
priority: high
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Jobs the user is actively pursuing (Interested/Applied) expire fast — often within days — but the automatic background availability check only re-verified jobs untouched for `availabilityStaleDays` (default 21) days. So a recently-captured pursued job that closes a week later stayed marked pursuing until the user checked manually.

Fix: `fetchStaleEligibleJobs` gains `alwaysCheckStatuses`, and the confirm-first background pass (`maybeFindStaleGoneJobs`) passes `["pursuing","applied"]` so those statuses are re-checked every run regardless of age (throttled to the daily interval + TASK-608 uncapped). Other statuses (e.g. new) still wait for the staleness window.

Context: a live check of all 85 Interested jobs found 8 genuinely expired (LinkedIn "no longer accepting"/404, Workday req gone, Greenhouse "page not found") — all now catchable by the detection logic (TASK-613 + existing gone-phrases); they were unmarked only because the auto-check hadn't reached them.
<!-- SECTION:DESCRIPTION:END -->
