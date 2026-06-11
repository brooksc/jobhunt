---
id: TASK-179
title: 'Settings: Wire or remove the LLM debug logging setting'
status: To Do
assignee: []
created_date: '2026-06-11 22:14'
labels:
  - audit
  - settings
  - llm
  - diagnostics
dependencies: []
references:
  - app/Views/Settings/SettingsView.swift
  - core/Settings/SettingsStore.swift
  - core/LLM/QueueActor.swift
  - core/LLM/Providers
priority: low
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
The LLM settings screen exposes `llmDebugLevel`, but runtime LLM/provider/queue paths do not appear to read it. Either route it into request/response logging diagnostics with privacy-safe levels, or remove the setting to avoid a no-op control.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Changing debug logging level has an observable effect on LLM diagnostics, or the control/key is removed.
- [ ] #2 Any verbose/full logging mode avoids leaking API keys and sensitive response bodies by default.
- [ ] #3 Tests or debug-mode documentation cover the supported logging levels.
<!-- AC:END -->
