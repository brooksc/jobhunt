---
id: TASK-441
title: 'Capture ingestion: Do not queue duplicate jobs for extraction by default'
status: Done
assignee: []
created_date: '2026-06-13 18:53'
updated_date: '2026-06-15 18:35'
labels:
  - audit
  - ingestion
  - llm-queue
dependencies: []
references:
  - core/Services/BackgroundStore.swift
  - core/Services/JobService.swift
  - tests/CoreTests/JobServiceTests.swift
modified_files:
  - core/Services/BackgroundStore.swift
  - tests/CoreTests/JobServiceTests.swift
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
`BackgroundStore.insertCaptureAtomically` creates a queued extraction `LLMRequest` for every newly inserted capture/job pair, including semantic duplicates that are immediately marked with `status == .duplicate` and `duplicateOfJobID != nil`. Duplicate jobs can therefore consume LLM queue slots and provider cost before a user reviews or unmarks them.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Semantic duplicate captures that create a `.duplicate` job do not automatically create extraction requests unless product policy explicitly requires it.
- [x] #2 Exact raw-hash duplicate captures continue to return the original capture/job result without creating a second job or request.
- [x] #3 Users can still explicitly queue extraction for a duplicate job when needed.
- [x] #4 Add focused tests for unique capture, exact duplicate capture, and semantic duplicate capture request creation behavior.
<!-- AC:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
insertCaptureAtomically now only inserts the queued extraction LLMRequest when duplicateOfJobID == nil, so a semantic-duplicate job (status .duplicate) no longer auto-consumes an LLM queue slot / provider cost before review (AC#1). The exact raw-hash duplicate path still early-returns the original capture/job without creating a second job or request (AC#2). A user can still explicitly re-run extraction on a duplicate job (resetExtraction clears the duplicate state and queues it) (AC#3). Test testIngestCapture_semanticDuplicateDoesNotQueueExtraction covers the semantic-dup path (2 jobs, exactly 1 flagged duplicate, exactly 1 extraction request); unique and exact-dup cases are covered by the existing TASK-448 tests (AC#4).
<!-- SECTION:FINAL_SUMMARY:END -->
