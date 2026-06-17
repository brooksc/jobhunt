---
id: TASK-479
title: 'Test infra: Add a store failure-injection seam to cover error paths'
status: Done
assignee: []
created_date: '2026-06-15 05:05'
updated_date: '2026-06-17 04:41'
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
- [x] #1 A test seam exists to make a store fetch/persist operation fail deterministically
- [x] #2 QueueActor fetch-failure (queueError, no false processingComplete) is covered by a test
- [x] #3 SettingsStore load-failure (loadError set, writes not persisted) is covered by a test
- [x] #4 AvailabilityChecker fetch-failure (timestamp not advanced) is covered by a test
<!-- AC:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Added narrow test-only fault-injection seams (AC#1): `BackgroundStore.setFetchFault(_:)` makes `fetch` throw deterministically, and `SettingsStore.loadFault` makes `loadCache`/`reload` fail — both default nil (no-op in production), since SwiftData's fetch can't be made to error on demand. Backfilled the deferred failure-path tests: AC#2 QueueActor.startProcessing on a fetch failure emits `.queueError` (not a false `.processingComplete`) [387]; AC#3 SettingsStore load failure sets `loadError` and gates persistence so a write doesn't clobber unread stored values [388]; AC#4 AvailabilityChecker.maybeRunStaleCheck on a fetch failure returns reason "fetch-error" and does NOT invoke the completion callback / advance the timestamp [389]. 817 CoreTests green; app builds.
<!-- SECTION:FINAL_SUMMARY:END -->
