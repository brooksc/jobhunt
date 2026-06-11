---
id: TASK-117
title: 'Persistence: Snapshot SwiftData models before LLM queue provider work'
status: Done
assignee: []
created_date: '2026-06-11 02:46'
updated_date: '2026-06-11 03:02'
labels:
  - persistence
  - swiftdata
  - queue
  - concurrency
dependencies: []
references:
  - core/LLM/QueueActor.swift
  - core/Services/BackgroundStore.swift
  - core/LLM/ExtractionEngine.swift
  - tests/CoreTests/ExtractionEngineTests.swift
priority: high
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
`QueueActor` fetches live SwiftData `Job` and `Resume` models, passes them into extraction/scoring provider workflows, and later persists results with separate store operations. This couples provider execution to SwiftData context lifetime and makes async/retry behavior harder to reason about. Convert queue processing to snapshot the needed model data into Sendable value types before provider calls, then persist results through explicit store/service methods.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 LLM extraction and fit-scoring provider calls receive Sendable value snapshots rather than live SwiftData model instances
- [x] #2 Queue processing persists extraction, fit score, attempt, and request-status updates through named store/service methods
- [x] #3 Retry, cancellation, auto-pause, and success notification behavior remains unchanged
- [x] #4 Tests cover at least one extraction path and one fit-scoring path using the new snapshot flow
- [x] #5 Swift strict concurrency remains clean without adding new unsafe Sendable escapes
<!-- AC:END -->
