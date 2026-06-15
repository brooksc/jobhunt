---
id: TASK-479
title: 'Test infra: Add a store failure-injection seam to cover error paths'
status: To Do
assignee: []
created_date: '2026-06-15 05:05'
labels:
  - tests
  - error-handling
  - infra
dependencies: []
references:
  - core/Models/BackgroundStore.swift
  - core/Settings/SettingsStore.swift
  - core/LLM/QueueActor.swift
  - core/Services/AvailabilityChecker.swift
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
TASK-387, TASK-388, and TASK-389 implemented correct behavior for store read/persist failures, but their failure-path ACs (AC#4 on each) could not be unit-tested: BackgroundStore is a concrete @ModelActor and SwiftData's fetch does not throw on demand (a ModelContext on a schema omitting a model returns empty rather than erroring), so there is no way to simulate a store error. Introduce a seam — e.g. a narrow protocol the store conforms to (fetch/update/insert/delete) that a test double can implement to throw — so the degraded-state paths get real coverage, then backfill the deferred AC#4 tests on 387/388/389.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 A test seam exists to make a store fetch/persist operation fail deterministically
- [ ] #2 QueueActor fetch-failure (queueError, no false processingComplete) is covered by a test
- [ ] #3 SettingsStore load-failure (loadError set, writes not persisted) is covered by a test
- [ ] #4 AvailabilityChecker fetch-failure (timestamp not advanced) is covered by a test
<!-- AC:END -->
