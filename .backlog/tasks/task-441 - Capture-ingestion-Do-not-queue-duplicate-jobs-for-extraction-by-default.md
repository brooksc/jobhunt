---
id: TASK-441
title: 'Capture ingestion: Do not queue duplicate jobs for extraction by default'
status: To Do
assignee: []
created_date: '2026-06-13 18:53'
labels:
  - audit
  - ingestion
  - llm-queue
dependencies: []
references:
  - core/Services/BackgroundStore.swift
  - core/Services/JobService.swift
  - tests/CoreTests/JobServiceTests.swift
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
`BackgroundStore.insertCaptureAtomically` creates a queued extraction `LLMRequest` for every newly inserted capture/job pair, including semantic duplicates that are immediately marked with `status == .duplicate` and `duplicateOfJobID != nil`. Duplicate jobs can therefore consume LLM queue slots and provider cost before a user reviews or unmarks them.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Semantic duplicate captures that create a `.duplicate` job do not automatically create extraction requests unless product policy explicitly requires it.
- [ ] #2 Exact raw-hash duplicate captures continue to return the original capture/job result without creating a second job or request.
- [ ] #3 Users can still explicitly queue extraction for a duplicate job when needed.
- [ ] #4 Add focused tests for unique capture, exact duplicate capture, and semantic duplicate capture request creation behavior.
<!-- AC:END -->
