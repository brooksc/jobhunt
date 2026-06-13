---
id: TASK-428
title: >-
  Startup lifecycle: Replace availability-check completion notification with
  explicit persistence callback
status: To Do
assignee: []
created_date: '2026-06-13 04:34'
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
- [ ] #1 Availability-check scheduling persists the last-check timestamp through an explicit dependency, callback, or app-layer coordinator rather than relying on a global notification for core-to-app communication.
- [ ] #2 The core availability checker remains testable with an injected session and does not require app-level global observers to maintain scheduling invariants.
- [ ] #3 Existing manual and automatic availability checks continue to update settings correctly.
- [ ] #4 Add focused tests that prove a completed automatic check updates the last-check timestamp through the explicit path.
<!-- AC:END -->
