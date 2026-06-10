---
id: TASK-090
title: >-
  Fix DataQualityView: Queue Re-extraction doesn't start processing; row tap
  breaks selection
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
HIGH: `Queue Re-extraction` toolbar button inserts `LLMRequest` rows but never calls `QueueActor.startProcessing()`. Jobs sit idle until user manually visits LLM Queue. Fix: call `startProcessing()` after enqueueing.

HIGH: `.onTapGesture` on each row navigates away before `List(selection:)` can register the tap — impossible to select a row by single-clicking for bulk actions. Fix: remove `.onTapGesture` from rows and use the List's built-in selection mechanism, navigating via `.onChange(of: selection)` or similar.

MEDIUM: `selectedJobIDs` is never cleared when list content changes — stale selection counts accumulate.

Files: `app/Views/DataQuality/DataQualityView.swift`
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Queue Re-extraction button enqueues jobs AND starts the queue processor
- [ ] #2 Single-clicking a row selects it for bulk actions
- [ ] #3 Double-clicking or navigating to detail works correctly
- [ ] #4 Selection is cleared when filtering changes the visible set
<!-- AC:END -->
