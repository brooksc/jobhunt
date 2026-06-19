---
id: TASK-511
title: 'Workflow: Surface background availability auto-expiry as a user notification'
status: To Do
assignee: []
created_date: '2026-06-19 01:30'
labels:
  - workflow
  - availability
  - notifications
dependencies: []
references:
  - docs/workflow.md
  - core/Services/AvailabilityChecker.swift
  - app/Platform/PlatformIntegration.swift
  - app/Shell/AppServices.swift
  - tests/CoreTests/AvailabilityCheckerTests.swift
priority: high
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Finding: `AvailabilityChecker.checkJobs` auto-marks pursuing jobs expired and posts `NotificationCenter.default` `.jobUnavailable`, and the workflow says a "Job Unavailable" notification is posted. However, production app code does not observe `.jobUnavailable`; `PlatformIntegration` only handles `QueueEvent.jobUnavailable`, and nothing bridges the availability checker event into that queue event or directly into a user notification.

Why this matters: Background availability checks can change job status while the user gets no visible notice, undermining trust in automatic expiry and making status changes look surprising later.

Suggested implementation: Wire the availability domain event to the macOS notification path. Options include making `PlatformIntegration` observe `.jobUnavailable` directly, or changing `AppServices`/`AvailabilityChecker` to emit a typed app event consumed by `PlatformIntegration`. Preserve the existing notification click behavior that opens the affected job when a job number is present.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 When periodic/background availability checking marks a pursuing job expired, the user receives a macOS "Job Unavailable" notification.
- [ ] #2 Clicking the notification opens the affected job when a job number is available; otherwise it navigates to the Jobs view or another sensible availability context.
- [ ] #3 The notification includes enough context to identify the job, such as job number and title when available.
- [ ] #4 Tests or a documented app-level verification cover the bridge from `AvailabilityChecker` auto-expiry to user-visible notification behavior.
- [ ] #5 The existing `AvailabilityChecker` unit tests for internal `.jobUnavailable` posting continue to pass or are updated to the new event boundary.
<!-- AC:END -->
