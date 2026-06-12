---
id: TASK-268
title: 'Capture: Preserve full posting context when selected text is present'
status: To Do
assignee: []
created_date: '2026-06-12 03:26'
labels:
  - audit
  - capture
  - llm
  - extraction
dependencies: []
references:
  - core/Util/Cleaning.swift
  - core/Services/JobService.swift
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
cleanDescription returns selected text immediately when non-empty, skipping visible page text and JSON-LD. This can make extraction operate on a snippet instead of the full posting. Preserve selected text as high-priority context while retaining visible and structured content, or introduce an explicit selection-only capture mode.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Selected text no longer silently discards visible page text and structured JobPosting data for normal captures.
- [ ] #2 If selection-only capture is desired, it is explicit in code and UI behavior.
- [ ] #3 Cleaning tests cover selected text combined with visible text and JSON-LD.
<!-- AC:END -->
