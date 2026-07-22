---
id: TASK-613
title: Investigate missed expiration detection for jobs 218 and 224
status: To Do
assignee: []
created_date: '2026-07-22 17:55'
labels:
  - bug
  - availability
  - workflow
dependencies: []
references:
  - core/Services/AvailabilityChecker.swift
  - app/Views/Jobs/JobsView.swift
  - app/Views/Settings/SettingsTab.swift
  - tests/CoreTests/AvailabilityCheckerTests.swift
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Jobs 218 and 224 visibly state “No longer accepting applications,” but are not being detected as expired/unavailable. AvailabilityChecker already includes a literal phrase, a generalized regex, and LinkedIn closed-job markup detection for this condition, so trace the complete path rather than adding another duplicate phrase blindly.

For each job, capture the stored status, source/canonical/application URL, title, scan path used (manual versus stale/background), final response URL/status, response body visible to URLSession, and resulting URLAvailabilityResult. Determine whether the miss comes from scan eligibility, URL selection, redirect/auth/bot handling, client-rendered content absent from the raw response, phrase/markup normalization, or failure to surface/persist the detected result.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 The missed result is reproduced for both jobs 218 and 224 using their persisted status, title, and selected availability-check URL.
- [ ] #2 The investigation records whether each job is eligible for the invoked scan path, including the manual pursuing/applied scope and the narrower background/stale scope.
- [ ] #3 For each job, the final HTTP status, redirect destination, relevant sanitized response evidence, and URLAvailabilityResult reason are documented.
- [ ] #4 If the closed text or structural marker is present in the response available to URLSession, both jobs are classified as gone without adding redundant or overly broad matching.
- [ ] #5 If the closed state is only client-rendered or hidden behind an auth/bot response, implement a host-scoped deterministic signal or classify the result as unverifiable with actionable feedback rather than silently available.
- [ ] #6 Running the applicable availability scan surfaces both jobs for expiration confirmation while they continue to report “No longer accepting applications.”
- [ ] #7 Focused regression fixtures cover the exact response behavior of jobs 218 and 224 and preserve live-posting, auth-wall, bot-challenge, redirect, and false-positive protections.
<!-- AC:END -->
