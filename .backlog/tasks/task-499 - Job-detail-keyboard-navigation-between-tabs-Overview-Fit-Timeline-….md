---
id: TASK-499
title: Comprehensive keyboard shortcuts and in-app shortcut reference
status: To Do
assignee: []
created_date: '2026-06-18 22:32'
updated_date: '2026-07-21 22:15'
labels:
  - ux
  - keyboard
  - hig
dependencies: []
references:
  - app/JobhuntApp.swift
  - app/Shell/AppCommands.swift
  - app/Shell/Router.swift
  - app/Shell/Sidebar.swift
  - app/Views/Jobs/JobsView.swift
  - app/Views/Detail/JobDetailView.swift
priority: high
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Design and implement a coherent macOS keyboard model for high-frequency navigation and job triage, preserving existing shortcuts where they do not conflict.

Required command set:
- Job-list navigation: ⌘1 All Jobs; ⌘2 New; ⌘3 Interested; ⌘4 Applied; ⌘5 Interview; ⌘6 Offer. Each command clears any active saved search, opens Jobs, and applies the named sidebar filter. Keep the existing Control-Command-number shortcuts for top-level app sections.
- Selected-job status progression: ⌃1 New; ⌃2 Interested; ⌃3 Applied; ⌃4 Interview; ⌃5 Offer; ⌃6 Rejected. These commands act on the current single or multiple selection and use the same status-change, feedback, event, and Undo path as the existing UI. Keep ⌃⌘A for Archive, making the common New-job triage workflow possible entirely from the keyboard: select a row, press ⌃2 to keep it as Interested or ⌃⌘A to Archive it. Passed, Closed, and Expired remain available from the status menu but do not need dedicated global shortcuts. Do not use ⌃I because Control-I is conventionally interpreted as Tab.
- Creation/search/export: ⌘N Add Job; ⌘F Find/Search Jobs; retain ⌘K as a search alias; ⌘⇧E Export Current List.
- Other selected-job actions: ⌘O Open Posting; retain ⌃⌘R Re-run Extraction and ⌘⌫ Delete with existing confirmation/undo behavior.
- Job-detail navigation: ⌃Tab and ⌃⇧Tab cycle forward/backward through Overview, Fit, Timeline, Description, Raw, and Compare when job detail is active. Escape continues to close transient detail/overlay UI where applicable.
- System conventions: retain ⌘, for Settings and standard macOS edit/window commands.

Add an in-app Keyboard Shortcuts overlay organized into Navigation, Change Status, Job Actions, Search and Data, and System sections. Pressing bare ? opens it when focus is not in a text-editing control; Escape and the standard close control dismiss it. Add “Keyboard Shortcuts” to the Help menu and have it open the same overlay. Keep the existing online JobHunt Help item, but remove or change its current ⌘? binding so it does not conflict. The overlay and menu labels must be driven by, or tested against, the actual command definitions so documentation cannot silently drift from behavior.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 ⌘1, ⌘2, and ⌘3 switch to All Jobs, New, and Interested respectively; ⌘4, ⌘5, and ⌘6 switch to Applied, Interview, and Offer.
- [ ] #2 Each Command-number job shortcut navigates to Jobs, clears an active saved search, applies the correct sidebar filter, and leaves the sidebar selection synchronized.
- [ ] #3 ⌃1 through ⌃6 change the current selected job or jobs to New, Interested, Applied, Interview, Offer, and Rejected respectively.
- [ ] #4 Keyboard status changes use the existing bulk status service and preserve status events, per-job prior state, success/error feedback, and actionable Undo behavior; they are disabled when there is no applicable job selection.
- [ ] #5 The primary keyboard triage flow works from the New list without a mouse: move selection using native list navigation, press ⌃2 to mark Interested or ⌃⌘A to Archive, then continue reviewing.
- [ ] #6 Passed, Closed, and Expired remain available through the status menu without dedicated shortcuts, and ⌃I is not registered because it conflicts with Tab behavior.
- [ ] #7 Existing top-level Control-Command-number navigation and existing ⌘N, ⌘F, ⌘K, ⌘⇧E, ⌘O, ⌃⌘R, ⌃⌘A, ⌘⌫, and ⌘, behavior remains available without conflicts.
- [ ] #8 When job detail is active, ⌃Tab and ⌃⇧Tab cycle through all detail tabs in both directions without conflicting with global navigation.
- [ ] #9 Pressing bare ? outside text-editing controls opens a keyboard-shortcuts overlay; typing ? in search fields, notes, or other editors inserts text and does not open the overlay.
- [ ] #10 The overlay groups and displays every supported app-specific shortcut, including the status progression, with human-readable key glyphs; it is keyboard and VoiceOver accessible and dismisses via Escape and a standard close control.
- [ ] #11 The Help menu contains a Keyboard Shortcuts command that opens the same overlay; online JobHunt Help remains available without retaining a conflicting shortcut.
- [ ] #12 Shortcut definitions and displayed help content share a single source of truth where practical, with focused tests for routing, status mutation and Undo, selection-dependent enablement, detail-tab cycling, text-entry suppression for bare ?, Help-menu presentation, overlay dismissal, and representative command execution.
<!-- AC:END -->
