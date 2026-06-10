---
id: TASK-085
title: >-
  Fix environment key injection: jobService and queueActor nil in Inspector, fix
  hardcoded extension status
status: To Do
assignee: []
created_date: '2026-06-10 07:31'
labels:
  - bug
  - ui-audit
dependencies: []
priority: high
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
HIGH: `JobInspectorView` reads `@Environment(\.jobService)` and `@Environment(\.queueActor)` but neither key is injected in ContentView. `Archive All` and `Re-run AI on All` silently no-op. Fix: inject both keys at ContentView level.

MEDIUM: `Extension: linked` in ContentView toolbar is a hardcoded static string. Should reflect actual extension connectivity state.

Files: `app/Views/ContentView.swift`, `app/Views/Jobs/JobInspectorView.swift`
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Archive All in multi-select inspector actually archives the selected jobs
- [ ] #2 Re-run AI on All actually enqueues LLM requests
- [ ] #3 Extension status label reflects real connectivity (or is removed if no connectivity signal exists)
<!-- AC:END -->
