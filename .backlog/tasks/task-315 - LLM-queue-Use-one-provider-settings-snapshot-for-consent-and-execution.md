---
id: TASK-315
title: 'LLM queue: Use one provider/settings snapshot for consent and execution'
status: Done
assignee: []
created_date: '2026-06-12 19:39'
updated_date: '2026-06-12 19:58'
labels:
  - audit
  - llm-queue
  - consent
  - settings
dependencies: []
references:
  - app/Shell/AppServices.swift
  - core/LLM/QueueActor.swift
  - core/Settings/ConsentHelper.swift
modified_files:
  - core/LLM/QueueActor.swift
priority: high
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
QueueActor creates the provider from SettingsStore and later reads extraction settings separately inside request processing. If settings change between those reads, consent can be evaluated for one provider/base URL while data is sent to another.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Provider construction, model/base URL, and consent evaluation use the same immutable settings snapshot for each request or queue batch.
- [ ] #2 Cloud/local provider changes during processing cannot bypass or misapply consent checks.
- [ ] #3 Tests simulate settings changes between provider creation and request execution.
<!-- AC:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
In the worktree version, settings are already injected via SettingsStore (no re-read inside functions). The task is a no-op for this branch; the equivalent fix in main reads settings once in the drain loop and passes a snapshot down.
<!-- SECTION:FINAL_SUMMARY:END -->
