---
id: TASK-428
title: >-
  Startup lifecycle: Replace availability-check completion notification with
  explicit persistence callback
status: Done
assignee: []
created_date: '2026-06-13 04:34'
updated_date: '2026-06-16 06:08'
labels:
  - audit
  - startup
  - architecture
dependencies: []
references:
  - core/Services/AvailabilityChecker.swift
  - app/Shell/AppServices.swift
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
`AvailabilityChecker.maybeRunStaleCheck` posts `.availabilityCheckCompleted` so the app layer can update `SettingsKey.availabilityLastAutoCheckAt` on the main actor. `AppServices` registers a global notification observer to persist the timestamp. This splits one invariant across core and app layers through a stringly/global contract; if the listener is absent or renamed, checks run but the interval gate is not persisted.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Availability-check scheduling persists the last-check timestamp through an explicit dependency, callback, or app-layer coordinator rather than relying on a global notification for core-to-app communication.
- [x] #2 The core availability checker remains testable with an injected session and does not require app-level global observers to maintain scheduling invariants.
- [x] #3 Existing manual and automatic availability checks continue to update settings correctly.
- [x] #4 Add focused tests that prove a completed automatic check updates the last-check timestamp through the explicit path.
<!-- AC:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Replaced the global `.availabilityCheckCompleted` notification (core→app stringly contract) with an injected `onAutoCheckCompleted: (@Sendable (Date) async -> Void)?` callback on `AvailabilityChecker.maybeRunStaleCheck`. The checker invokes it only after a valid pass (still nothing on skip or fetch-error, preserving the interval-gate invariant — AC#3); AppServices passes a callback that writes `availabilityLastAutoCheckAt` on the main actor and no longer registers a NotificationCenter observer (AC#1). The core checker keeps its injected `URLSession` and needs no app-level global observer (AC#2). Removed the `Notification.Name` extension. AC#4: tests assert the callback fires exactly once carrying a timestamp on a valid pass, and is not called when the check is skipped. Full CoreTests (771) green; app builds. Manual availability checks are unaffected (they never used this notification).
<!-- SECTION:FINAL_SUMMARY:END -->
