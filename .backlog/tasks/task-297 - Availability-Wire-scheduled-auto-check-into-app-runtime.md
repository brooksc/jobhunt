---
id: TASK-297
title: 'Availability: Wire scheduled auto-check into app runtime'
status: Done
assignee: []
created_date: '2026-06-12 05:01'
updated_date: '2026-06-12 05:47'
labels:
  - audit
  - availability
  - settings
dependencies: []
references:
  - core/Services/AvailabilityChecker.swift
  - app/Shell/AppServices.swift
priority: high
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
The settings UI exposes automatic availability checking, and AvailabilityChecker.maybeRunStaleCheck implements the scheduled path, but no production caller was found. Enablement can therefore appear to succeed while no automatic checks run.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 A production runtime path invokes AvailabilityChecker.maybeRunStaleCheck on an appropriate cadence or launch/resume trigger when availabilityAutoCheckEnabled is true.
- [ ] #2 availabilityLastAutoCheckAt is updated only after an attempted scheduled check completes.
- [ ] #3 Add or update tests covering the production scheduling trigger and disabled/enabled behavior.
<!-- AC:END -->
