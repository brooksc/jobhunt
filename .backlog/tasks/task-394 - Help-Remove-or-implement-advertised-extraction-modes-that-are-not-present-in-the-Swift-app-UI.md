---
id: TASK-394
title: >-
  Help: Remove or implement advertised extraction modes that are not present in
  the Swift app UI
status: Done
assignee: []
created_date: '2026-06-12 23:02'
updated_date: '2026-06-15 18:40'
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
modified_files:
  - app/Views/Help/HelpView.swift
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Help advertises Full extraction, Missing fields only, and Fit score only modes, but the current Swift app exposes extract and fit request types through Re-run AI / fit scoring flows rather than those named controls. Either update Help to match current UI or implement the advertised modes explicitly.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Help no longer points users to missing extraction-mode controls.
- [x] #2 If named modes remain documented, matching UI controls and request behavior exist.
- [x] #3 Troubleshooting guidance for failed extraction/fit scoring uses current screen and command names.
- [x] #4 A smoke review confirms the Help workflow text maps to visible app controls.
<!-- AC:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Help's Extraction & Scoring section no longer advertises the nonexistent "Full extraction / Missing fields only / Fit score only" mode controls. It now describes the actual UI: new captures extract automatically; Re-run AI (job detail pane, or a selection in Jobs/Data Quality) re-processes; Score against resume on the Fit tab recomputes fit without re-extracting (AC#1/#2/#3). Those control names match visible app commands (AC#4).
<!-- SECTION:FINAL_SUMMARY:END -->
