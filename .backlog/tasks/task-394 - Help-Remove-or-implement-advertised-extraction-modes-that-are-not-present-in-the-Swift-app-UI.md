---
id: TASK-394
title: >-
  Help: Remove or implement advertised extraction modes that are not present in
  the Swift app UI
status: To Do
assignee: []
created_date: '2026-06-12 23:02'
labels:
  - audit
  - docs
  - help
  - llm
dependencies: []
references:
  - app/Views/Help/HelpView.swift
  - core/Models/Enums.swift
  - app/Views/Jobs/JobsView.swift
  - app/Views/Detail/JobDetailView.swift
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Help advertises Full extraction, Missing fields only, and Fit score only modes, but the current Swift app exposes extract and fit request types through Re-run AI / fit scoring flows rather than those named controls. Either update Help to match current UI or implement the advertised modes explicitly.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Help no longer points users to missing extraction-mode controls.
- [ ] #2 If named modes remain documented, matching UI controls and request behavior exist.
- [ ] #3 Troubleshooting guidance for failed extraction/fit scoring uses current screen and command names.
- [ ] #4 A smoke review confirms the Help workflow text maps to visible app controls.
<!-- AC:END -->
