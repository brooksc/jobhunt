---
id: TASK-316
title: 'LLM queue: Prevent cancellation from being overwritten by running transition'
status: To Do
assignee: []
created_date: '2026-06-12 19:39'
labels:
  - audit
  - llm-queue
  - cancellation
dependencies: []
references:
  - core/LLM/QueueActor.swift
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
fetchQueuedRequests snapshots queued items, then processRequest marks by ID as running without requiring the row to still be queued. A cancellation after fetch but before the running transition can be overwritten.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 The queued-to-running transition is conditional on the request still being queued.
- [ ] #2 If a request was cancelled after fetch, processing skips it without invoking the provider.
- [ ] #3 Regression tests cover cancellation between fetch and running transition.
<!-- AC:END -->
