---
id: TASK-313
title: 'LLM queue: Preserve retry and retry-exhausted states after failures'
status: To Do
assignee: []
created_date: '2026-06-12 19:38'
labels:
  - audit
  - llm-queue
  - retries
dependencies: []
references:
  - core/LLM/QueueActor.swift
  - tests/CoreTests/ExtractionEngineTests.swift
priority: high
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
processExtractRequest and processFitRequest requeue retryable failures or mark retryExhausted, then throw. The outer processRequest catch calls markRequestFailed and overwrites those states with failed, so retries may not actually retry and final failures can lose retryExhausted status.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Retryable provider failures leave the LLMRequest in queued status with incremented attempt until maxRetries is reached.
- [ ] #2 Final failures remain retryExhausted rather than being overwritten to failed.
- [ ] #3 Tests cover retryable extraction and fit failures across attempts, including final exhausted state.
<!-- AC:END -->
