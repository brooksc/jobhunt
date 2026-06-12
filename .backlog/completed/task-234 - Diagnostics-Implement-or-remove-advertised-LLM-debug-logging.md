---
id: TASK-234
title: 'Diagnostics: Implement or remove advertised LLM debug logging'
status: Done
assignee: []
created_date: '2026-06-12 01:50'
updated_date: '2026-06-12 02:08'
labels:
  - diagnostics
  - docs
  - llm
dependencies: []
references:
  - README.md
  - app/Views/Help/HelpView.swift
  - app/Views/Settings/DebugTab.swift
  - core/Settings/SettingsStore.swift
  - core/Models/Setting.swift
priority: high
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
README and Help direct users to LLM debug logs and a Settings > Debug logging control, but the Debug tab only shows counts and no logger appears to write ~/Library/Logs/Jobhunt. Either implement privacy-safe debug logging and controls, or remove/update the documentation.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Settings > Debug contains a real LLM debug logging control or the Help/README references are removed.
- [ ] #2 If implemented, debug logs are written to the documented location and avoid raw job/resume text and API keys by default.
- [ ] #3 The LLM Queue and Help screens point users to the actual diagnostics path.
- [ ] #4 Tests or a manual verification checklist confirm the debug-log path works.
<!-- AC:END -->
