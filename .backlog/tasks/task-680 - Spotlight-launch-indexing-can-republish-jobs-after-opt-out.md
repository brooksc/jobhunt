---
id: TASK-680
title: Spotlight launch indexing can republish jobs after opt-out
status: To Do
assignee: []
created_date: '2026-08-21 20:26'
labels:
  - bug
  - spotlight
  - privacy
  - macos
dependencies: []
references:
  - TASK-590
  - app/Platform/SpotlightIndexer.swift
  - app/Views/Settings/DataSettingsTab.swift
modified_files:
  - app/Shell/AppServices.swift
  - app/Platform/SpotlightIndexer.swift
  - app/Views/Settings/DataSettingsTab.swift
  - tests/CoreTests/SpotlightEntryTests.swift
priority: high
type: bug
ordinal: 54000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Privacy regression found during the 2026-08-21 code review. Launch indexing checks the user's setting before asynchronous work, while replacement performs a later asynchronous clear-and-index sequence. If the user disables Spotlight during either gap, the opt-out clear can finish and captured job entries can subsequently be published again.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Turning off Spotlight publishing prevents every in-flight launch indexing operation from publishing job data afterward
- [ ] #2 The disabled state wins when it changes during job retrieval, index clearing, or index replacement
- [ ] #3 Turning the setting off removes existing Jobhunt Spotlight entries
- [ ] #4 Re-enabling the setting permits a later explicit or launch-time rebuild
- [ ] #5 A deterministic regression test exercises opt-out during a delayed indexing operation
<!-- AC:END -->
