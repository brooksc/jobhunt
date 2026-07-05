---
id: TASK-595
title: >-
  availability: generalize gone-detection to Workable + LinkedIn closed-job
  banner
status: Done
assignee: []
created_date: '2026-07-05 02:24'
labels:
  - availability
dependencies: []
modified_files:
  - core/Services/AvailabilityChecker.swift
  - tests/CoreTests/AvailabilityCheckerTests.swift
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Follow-on to TASK-594 (job #37 Greenhouse). Two more real-world expired postings weren't auto-flagged:

- Job #130 (LinkedIn, Pulumi "Principal Product Manager"): LinkedIn's public guest view returns HTTP 200 with a structured `<figure class="closed-job">…<figcaption class="closed-job__flavor--closed">No longer accepting applications</figcaption>` banner and no Apply CTA. The visible phrase was already matched by `bodyGoneReason`, so the job was already detectable on re-check; added the structural `closed-job__flavor` marker (host-scoped to linkedin.com) as a wording/locale-independent backstop.
- Workable: a removed/unknown posting 302-redirects to `/oops` at HTTP 200 — missed by status/body/redirect heuristics. Added a Workable rule to `isBoardErrorLandingURL`.

Probed the major ATS hosts to ground the work: Greenhouse (`?error=true`, already handled), Lever + SmartRecruiters (real 404, already handled by status codes), Workable (`/oops`, added), Ashby (client-rendered SPA returning a generic 200 shell with no server-side gone signal — documented as a known limitation, not detectable without JS rendering).</description>
<parameter name="acceptanceCriteria">["isBoardErrorLandingURL flags Workable /oops landing without false-positiving on live Workable posting paths or /oops on other hosts", "LinkedIn closed-job structural marker flags a closed guest-view posting even when the banner text is non-English, and does not false-positive on a live LinkedIn guest view or on the closed-job class on non-LinkedIn hosts", "Unit + end-to-end tests added; CoreTests fast gate green; SwiftLint/SwiftFormat clean"]
<!-- SECTION:DESCRIPTION:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Extended AvailabilityChecker.isBoardErrorLandingURL to cover Workable's /oops error landing (Greenhouse ?error=true unchanged), and added AvailabilityChecker.isLinkedInClosedJob to detect LinkedIn's structured closed-job banner (host-scoped, wording/locale-independent) wired into checkURL before the auth-wall guard. Ashby left as a documented limitation (client-rendered SPA, no server-side signal). Added 5 tests; full CoreTests AvailabilityChecker suites pass; lint/format clean. Jobs #37 and #130 both resolve to expired on re-check.
<!-- SECTION:FINAL_SUMMARY:END -->
