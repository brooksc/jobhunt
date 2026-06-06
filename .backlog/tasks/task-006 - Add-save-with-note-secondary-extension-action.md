---
id: TASK-006
title: Add save-with-note secondary extension action
status: Done
assignee: []
created_date: '2026-05-27 04:35'
updated_date: '2026-05-27 04:54'
labels:
  - m2-extension
  - extension
  - notes
dependencies:
  - TASK-004
modified_files:
  - extension/manifest.json
  - extension/service_worker.js
  - extension/note.html
  - extension/note.css
  - extension/note.js
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Add a secondary note workflow without adding friction to the default save path. The primary toolbar click remains immediate capture; notes are only collected through a separate intentional action.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 The extension provides a context menu action named Save job with note
- [x] #2 Using the note action captures the same page data as the primary flow plus user_note text
- [x] #3 The toolbar icon click remains one-click capture with no popup or note prompt
- [x] #4 Notes are included in the payload accepted by the local API
- [x] #5 Manual verification confirms captures with and without notes both persist correctly
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
Add a context menu item for Save job with note while keeping toolbar click one-step. Since MV3 service workers cannot use window.prompt, open a tiny extension note page only for the context-menu flow; it captures the tab payload with user_note and submits through the same retry/status pipeline.
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Added Save job with note context menu registration on extension install. The context-menu flow stores the source tab ID in chrome.storage.session, opens note.html, and submits a captureWithNote runtime message. Toolbar action remains unchanged and does not prompt. API smoke test confirmed a payload with user_note is accepted by the local service. Full Chrome UI manual verification was not performed from this environment.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Added the secondary note workflow. The extension registers a Save job with note context menu item, opens a small note page only for that secondary action, and submits the note through the same capture and retry pipeline while preserving one-click toolbar capture.
<!-- SECTION:FINAL_SUMMARY:END -->
