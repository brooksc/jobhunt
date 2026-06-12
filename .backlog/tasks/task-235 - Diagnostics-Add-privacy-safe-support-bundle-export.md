---
id: TASK-235
title: 'Diagnostics: Add privacy-safe support bundle export'
status: To Do
assignee: []
created_date: '2026-06-12 01:50'
labels:
  - diagnostics
  - support
  - privacy
dependencies: []
references:
  - app/Views/Settings/DebugTab.swift
  - app/Views/Queue/LLMQueueView.swift
  - app/Shell/AppServices.swift
  - CONTRIBUTING.md
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
The app has queue errors, attempt history, server state, app version, and Debug counts, but no single support export. Add a diagnostics bundle that gathers useful failure context without raw job/resume content or API keys.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 A user-accessible action exports or copies diagnostics with app version/build, provider type/model, server status, queue summary, recent sanitized errors, and key settings state.
- [ ] #2 Diagnostics exclude raw captured text, resume text, API keys, and provider response bodies by default.
- [ ] #3 The export includes timestamps and enough context to correlate queue failures with attempts.
- [ ] #4 Help/CONTRIBUTING explains what to include when filing bugs.
<!-- AC:END -->
