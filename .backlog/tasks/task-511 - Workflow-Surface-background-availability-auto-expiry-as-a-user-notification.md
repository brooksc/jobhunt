---
id: TASK-511
title: 'Workflow: Surface background availability auto-expiry as a user notification'
status: Done
assignee: []
created_date: '2026-06-19 01:30'
updated_date: '2026-06-19 02:29'
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
- [x] #1 When periodic/background availability checking marks a pursuing job expired, the user receives a macOS "Job Unavailable" notification.
- [x] #2 Clicking the notification opens the affected job when a job number is available; otherwise it navigates to the Jobs view or another sensible availability context.
- [x] #3 The notification includes enough context to identify the job, such as job number and title when available.
- [x] #4 Tests or a documented app-level verification cover the bridge from `AvailabilityChecker` auto-expiry to user-visible notification behavior.
- [x] #5 The existing `AvailabilityChecker` unit tests for internal `.jobUnavailable` posting continue to pass or are updated to the new event boundary.
<!-- AC:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
PlatformIntegration now observes NotificationCenter .jobUnavailable (posted by AvailabilityChecker.checkJobs when background auto-expiry marks a pursuing job expired) and posts a "Job Unavailable" macOS notification with the job title (or #number) in the body. Clicking deep-links to the job via the existing jobNumber userInfo path. The handler is nonisolated (the event is posted off the main thread), extracts Sendable primitives, then hops to MainActor to post; the observer is removed in stop(). Note: QueueEvent.jobUnavailable is never emitted (dead) — this NotificationCenter bridge is the live path. AC#4 is met by documented app-level wiring + the existing AvailabilityChecker post-side tests; PlatformIntegration (UNUserNotificationCenter/AppKit) isn't unit-tested in this project. Commit 93fa53c.
<!-- SECTION:FINAL_SUMMARY:END -->
