---
id: TASK-613
title: 'Investigate missed expiration detection for jobs 195, 218, and 224'
status: To Do
assignee: []
created_date: '2026-07-22 17:55'
updated_date: '2026-07-22 17:55'
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
Three jobs visibly indicate that their postings are unavailable but are not being detected as expired/unavailable:
- Job 195: “The page you are looking for doesn't exist.”
- Jobs 218 and 224: “No longer accepting applications.”

AvailabilityChecker already includes literal/regex handling for “No longer accepting applications,” LinkedIn closed-job markup, and generic page/job-not-found responses. Trace the complete path before adding patterns blindly.

For each job, capture the stored status, source/canonical/application URL, title, scan path used (manual versus stale/background), final response URL/status, response body visible to URLSession, and resulting URLAvailabilityResult. Determine whether the miss comes from scan eligibility, URL selection, redirect/auth/bot handling, client-rendered content absent from the raw response, phrase/markup normalization, or failure to surface/persist the detected result. If job 195 requires a new missing-page phrase, scope it to clear page/posting-not-found context or the relevant host so unrelated “doesn't exist” copy cannot expire a live job.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 The missed result is reproduced for jobs 195, 218, and 224 using each record’s persisted status, title, and selected availability-check URL.
- [ ] #2 The investigation records whether each job is eligible for the invoked scan path, including the manual pursuing/applied scope and the narrower background/stale scope.
- [ ] #3 For each job, the final HTTP status, redirect destination, relevant sanitized response evidence, and URLAvailabilityResult reason are documented.
- [ ] #4 If the closed text or structural marker is present in the response available to URLSession, jobs 218 and 224 are classified as gone without adding redundant or overly broad matching.
- [ ] #5 Job 195 is classified as gone when the fetched posting response clearly states “The page you are looking for doesn't exist,” using a context-aware or host-scoped rule that does not match unrelated uses of “doesn't exist.”
- [ ] #6 If any unavailable state is only client-rendered or hidden behind an auth/bot response, implement a host-scoped deterministic signal or classify the result as unverifiable with actionable feedback rather than silently available.
- [ ] #7 Running the applicable availability scan surfaces all three jobs for expiration confirmation while their source pages continue to report these unavailable states.
- [ ] #8 Focused regression fixtures cover the exact response behavior of jobs 195, 218, and 224 and preserve live-posting, auth-wall, bot-challenge, redirect, and false-positive protections.
<!-- AC:END -->
