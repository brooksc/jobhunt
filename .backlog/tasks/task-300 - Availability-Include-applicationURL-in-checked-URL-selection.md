---
id: TASK-300
title: 'Availability: Include applicationURL in checked URL selection'
status: To Do
assignee: []
created_date: '2026-06-12 05:01'
labels:
  - audit
  - availability
  - url-selection
dependencies: []
references:
  - core/Services/AvailabilityChecker.swift
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Manual and automatic availability paths check capture.canonicalURL or capture.url but ignore job.applicationURL. For extracted apply links, this can check the wrong page and produce misleading availability results.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Define URL precedence for availability checks, including when job.applicationURL should be preferred or considered.
- [ ] #2 Both findGoneJobs and checkJobs use the same URL-selection helper.
- [ ] #3 Add tests covering jobs with applicationURL, canonicalURL, and source capture URL combinations.
<!-- AC:END -->
