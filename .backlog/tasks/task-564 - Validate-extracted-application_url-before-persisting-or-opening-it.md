---
id: TASK-564
title: Validate extracted application_url before persisting or opening it
status: To Do
assignee: []
created_date: '2026-06-20 00:56'
labels:
  - audit
  - llm
  - extraction
  - validation
  - url
dependencies: []
references:
  - 'core/LLM/ExtractionDTO.swift:56'
  - 'core/LLM/ExtractionEngine.swift:212'
  - 'core/LLM/QueueActor.swift:584'
  - 'core/Services/JobURLPolicy.swift:22'
  - 'app/Views/Detail/JobDetailView.swift:447'
modified_files:
  - core/LLM/ExtractionDTO.swift
  - core/LLM/ExtractionEngine.swift
  - core/LLM/QueueActor.swift
  - core/Services/URLNormalizer.swift
  - tests/CoreTests/ExtractionEngineTests.swift
  - tests/CoreTests/URLNormalizerTests.swift
  - tests/CoreTests/JobURLPolicyTests.swift
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Finding: `ExtractionDTO` accepts `application_url` as any string (`core/LLM/ExtractionDTO.swift:56`), `ExtractionEngine.extract` forwards it into `ExtractionResult` (`core/LLM/ExtractionEngine.swift:212`), and `QueueActor` persists it directly to `job.applicationURL` unless manually overridden (`core/LLM/QueueActor.swift:584`). That field is later used by URL precedence and open/apply surfaces (`core/Services/JobURLPolicy.swift:22`, `app/Views/Detail/JobDetailView.swift:447`). Captured URLs are protected by `URLNormalizer.validatedForIngestion`, but provider-extracted application URLs are not.

Why important: LLM output is untrusted. A malformed, schemeless, non-http(s), or prompt-injected string can become a stored application URL and then shadow the safe capture/canonical URL in apply/availability precedence. Even if `URL(string:)` refuses some bad values at open time, the persisted field can still confuse exports, availability checks, and UI behavior.

Suggested implementation: add a value-level URL validation path for extracted/application URLs, likely reusing `URLNormalizer` with a policy that accepts only `http`/`https` absolute URLs. Normalize valid application URLs before persistence and drop or quarantine invalid ones into `extractedJSON`/diagnostics rather than `job.applicationURL`. Add extraction tests for valid HTTPS, schemeless, `javascript:`, and malformed application URLs, plus URL policy tests proving invalid extracted application URLs do not shadow capture/canonical URLs.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Only absolute `http`/`https` extracted application URLs are persisted into `job.applicationURL`.
- [ ] #2 Invalid extracted application URLs do not shadow capture/canonical URLs in apply, display, or availability-check precedence.
- [ ] #3 Tests cover valid, schemeless, non-http(s), and malformed extracted application URL outputs.
<!-- AC:END -->
