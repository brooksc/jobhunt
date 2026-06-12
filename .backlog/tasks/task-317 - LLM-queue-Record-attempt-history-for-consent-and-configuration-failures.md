---
id: TASK-317
title: 'LLM queue: Record attempt history for consent and configuration failures'
status: Done
assignee: []
created_date: '2026-06-12 19:40'
updated_date: '2026-06-12 19:58'
labels:
  - audit
  - llm-queue
  - history
  - consent
dependencies: []
references:
  - core/LLM/QueueActor.swift
modified_files:
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

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Before the resume-missing failure path in processFitRequest, create and insert a LLMRequestAttempt with status .failed, linked to the LLMRequest and Job, so pre-provider failures have attempt history.
<!-- SECTION:FINAL_SUMMARY:END -->
