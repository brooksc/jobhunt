---
id: TASK-536
title: 'LLM: record attempt history when cloud consent blocks a request'
status: To Do
assignee: []
created_date: '2026-06-19 04:56'
labels:
  - audit
  - llm
  - privacy
  - consent
  - queue
dependencies: []
references:
  - core/LLM/QueueActor.swift
  - core/Models/LLMRequestAttempt.swift
  - tests/CoreTests/ExtractionEngineTests.swift
  - docs/MAS-VALIDATION.md
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Finding: the consent gate correctly prevents cloud data transmission, but the failure path bypasses attempt-history persistence. In both extraction and fit processing, when `ConsentHelper.isConsented(...)` returns false, `QueueActor` calls `markRequestFailed(...)` and returns. Unlike provider failures, missing-resume fit failures, and other pre-provider paths, this does not insert an `LLMRequestAttempt` row. Existing docs reference consent enforcement, and a completed backlog item (`TASK-317`) says consent/configuration failures should be recorded, but the current code does not record an attempt for the consent-blocked path.

Why this matters: privacy and App Store compliance boundaries need an auditable trail showing that a request was blocked before sending data. Without an attempt record, diagnostics can show a failed request without the structured context that other failures have, and future maintenance can accidentally weaken the consent boundary because tests only assert request status.

Suggested implementation: add a small helper for pre-provider blocked attempts and call it from both extraction and fit consent guards. The attempt should be linked to the request and job, use a sanitized consent error, include request type/attempt number, and include provider/model/base URL provenance where safe. Keep the request status behavior unchanged: consent-blocked work should fail the request, not retry or auto-send later without a new user action.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Consent-blocked extraction requests persist a failed `LLMRequestAttempt` linked to the request and job.
- [ ] #2 Consent-blocked fit requests persist a failed `LLMRequestAttempt` linked to the request and job.
- [ ] #3 The persisted error remains sanitized and clearly states that cloud LLM consent was not granted.
- [ ] #4 Consent-blocked requests do not call the provider, do not retry automatically, and still end in failed request status.
- [ ] #5 Tests assert both request status and attempt history for extraction and fit consent failures.
- [ ] #6 The implementation avoids duplicating pre-provider attempt-building logic across extraction and fit paths.
<!-- AC:END -->
