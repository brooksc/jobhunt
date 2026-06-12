---
id: TASK-317
title: 'LLM queue: Record attempt history for consent and configuration failures'
status: To Do
assignee: []
created_date: '2026-06-12 19:40'
labels:
  - audit
  - llm-queue
  - history
  - consent
dependencies: []
references:
  - core/LLM/QueueActor.swift
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Consent denial and other pre-provider failures call markRequestFailed directly without creating an LLMRequestAttempt. The request has an error, but attempt history is incomplete.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Consent-denied and pre-provider validation failures create an attempt record or an explicitly modeled request event.
- [ ] #2 Attempt history clearly distinguishes blocked-by-consent/configuration from provider execution failures.
- [ ] #3 Tests verify attempt history for consent-denied extraction and fit requests.
<!-- AC:END -->
