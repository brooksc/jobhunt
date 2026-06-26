---
id: TASK-536
title: 'LLM: record attempt history when cloud consent blocks a request'
status: Done
assignee: []
created_date: '2026-06-19 04:56'
updated_date: '2026-06-26 07:09'
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
- [x] #1 Consent-blocked extraction requests persist a failed `LLMRequestAttempt` linked to the request and job.
- [x] #2 Consent-blocked fit requests persist a failed `LLMRequestAttempt` linked to the request and job.
- [x] #3 The persisted error remains sanitized and clearly states that cloud LLM consent was not granted.
- [x] #4 Consent-blocked requests do not call the provider, do not retry automatically, and still end in failed request status.
- [x] #5 Tests assert both request status and attempt history for extraction and fit consent failures.
- [x] #6 The implementation avoids duplicating pre-provider attempt-building logic across extraction and fit paths.
<!-- AC:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Added QueueActor.recordConsentBlockedAttempt(requestID:jobID:requestType:attempt:model:baseURL:startedAt:), called from both the extraction and fit consent gates before markRequestFailed. It persists a failed LLMRequestAttempt linked to the request and job (AC#1/#2), with the sanitized ConsentError.notConsented message (AC#3) and the effective endpoint (TASK-537 AC#3). The provider is still never called and there's no auto-retry — the request ends failed (AC#4). One shared helper covers both paths (AC#6). Tests: testExtractRequest_consentMissing_marksRequestFailedAndRecordsAttempt and the extended testFitRequest_consentMissing_marksRequestFailed assert request status + a failed attempt carrying the consent error and base URL (AC#5). Full CoreTests (943) green; lint clean. Commit 3102e06.
<!-- SECTION:FINAL_SUMMARY:END -->
