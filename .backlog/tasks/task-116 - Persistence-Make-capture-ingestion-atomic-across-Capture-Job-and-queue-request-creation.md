---
id: TASK-116
title: >-
  Persistence: Make capture ingestion atomic across Capture, Job, and queue
  request creation
status: To Do
assignee: []
created_date: '2026-06-11 02:46'
labels:
  - persistence
  - swiftdata
  - architecture
  - correctness
dependencies: []
references:
  - core/Services/JobService.swift
  - core/Services/BackgroundStore.swift
  - core/LLM/QueueActor.swift
  - tests/CoreTests/JobServiceTests.swift
priority: high
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
`JobService.ingestCapture` currently calculates `maxJobNumber + 1`, then saves `Capture` and `Job` with separate `BackgroundStore.insert` calls before enqueueing extraction. This can race under concurrent captures and can leave partially persisted data if one step succeeds and a later step fails. Move capture ingestion into a single persistence boundary that creates the capture, job, assigned job number, and extraction queue request consistently.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Concurrent capture ingestion cannot assign duplicate `jobNumber` values
- [ ] #2 A successful ingestion persists a linked `Capture`, `Job`, and extraction `LLMRequest` as one consistent unit
- [ ] #3 If ingestion fails, it does not leave an orphaned capture, orphaned job, or missing queue request
- [ ] #4 Duplicate detection behavior remains unchanged for raw-hash and cleaned-hash duplicates
- [ ] #5 Focused tests cover concurrent ingestion and failure/partial-write behavior
<!-- AC:END -->
