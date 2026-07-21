---
id: TASK-603
title: Investigate availability false positive for job 122
status: To Do
assignee: []
created_date: '2026-07-21 21:41'
labels:
  - bug
  - availability
  - workflow
dependencies: []
references:
  - core/Services/AvailabilityChecker.swift
  - tests/CoreTests/AvailabilityCheckerTests.swift
  - app/Views/Jobs/JobsView.swift
  - app/Views/Settings/SettingsTab.swift
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Job 122 is reported by the availability scan as no longer available, but opening its source URL shows that the posting is still available. Reproduce the check using job 122's stored URL and title, capture which AvailabilityChecker heuristic and final response URL/body triggered the result, and correct the false-positive classification without weakening detection for genuinely removed postings.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 The availability result for job 122 is reproduced and the exact status-code, body-pattern, redirect, board-specific, auth-wall, or title heuristic responsible for the false positive is documented.
- [ ] #2 While the source posting remains available, rechecking job 122 classifies it as available and does not propose or apply an expired/not-available status.
- [ ] #3 A focused regression test covers a sanitized fixture matching job 122's response/redirect behavior.
- [ ] #4 Existing detection for genuine 404/410 responses, explicit closed-posting content, and known removed-posting redirects remains covered and passing.
<!-- AC:END -->
