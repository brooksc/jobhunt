---
id: TASK-499
title: Comprehensive keyboard shortcuts and in-app shortcut reference
status: To Do
assignee: []
created_date: '2026-06-18 22:32'
updated_date: '2026-07-21 21:48'
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
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Design and implement a coherent macOS keyboard model for high-frequency navigation and job actions, preserving existing shortcuts where they do not conflict. Plain Command-number shortcuts navigate the active job workflow: ⌘1 All Jobs, ⌘2 New, ⌘3 Interested, ⌘4 Applied, ⌘5 Interview, and ⌘6 Offer. Keep the existing Control-Command-number shortcuts for top-level app sections.

Required command set:
- Navigation: ⌘1 All Jobs; ⌘2 New; ⌘3 Interested; ⌘4 Applied; ⌘5 Interview; ⌘6 Offer. Each command clears any active saved search, opens Jobs, and applies the named sidebar filter.
- Creation/search/export: ⌘N Add Job; ⌘F Find/Search Jobs; retain ⌘K as a search alias; ⌘⇧E Export Current List.
- Selected-job actions: ⌘O Open Posting; ⌃⌘I Mark Interested; ⌃⌘P Mark Applied; retain ⌃⌘R Re-run Extraction, ⌃⌘A Archive, and ⌘⌫ Delete with existing confirmation/undo behavior.
- Job-detail navigation: ⌃Tab and ⌃⇧Tab cycle forward/backward through Overview, Fit, Timeline, Description, Raw, and Compare when job detail is active. Escape continues to close transient detail/overlay UI where applicable.
- System conventions: retain ⌘, for Settings and standard macOS edit/window commands.

Add an in-app Keyboard Shortcuts overlay organized into Navigation, Jobs, Search and Data, and System sections. Pressing bare ? opens it when focus is not in a text-editing control; Escape and the standard close control dismiss it. Add “Keyboard Shortcuts” to the Help menu and have it open the same overlay. Keep the existing online JobHunt Help item, but remove or change its current ⌘? binding so it does not conflict. The overlay and menu labels must be driven by, or tested against, the actual command definitions so documentation cannot silently drift from behavior.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 ⌘1, ⌘2, and ⌘3 switch to All Jobs, New, and Interested respectively; ⌘4, ⌘5, and ⌘6 switch to Applied, Interview, and Offer.
- [ ] #2 Each Command-number job shortcut navigates to Jobs, clears an active saved search, applies the correct sidebar filter, and leaves the sidebar selection synchronized.
- [ ] #3 Existing top-level Control-Command-number navigation and existing ⌘N, ⌘F, ⌘K, ⌘⇧E, ⌘O, ⌃⌘R, ⌃⌘A, ⌘⌫, and ⌘, behavior remains available without conflicts.
- [ ] #4 Selected jobs support ⌃⌘I for Mark Interested and ⌃⌘P for Mark Applied, using the same service, selection, feedback, confirmation, and undo behavior as their menu or context-menu actions.
- [ ] #5 When job detail is active, ⌃Tab and ⌃⇧Tab cycle through all detail tabs in both directions without conflicting with global navigation.
- [ ] #6 Pressing bare ? outside text-editing controls opens a keyboard-shortcuts overlay; typing ? in search fields, notes, or other editors inserts text and does not open the overlay.
- [ ] #7 The overlay groups and displays every supported app-specific shortcut with human-readable key glyphs, is keyboard and VoiceOver accessible, and dismisses via Escape and a standard close control.
- [ ] #8 The Help menu contains a Keyboard Shortcuts command that opens the same overlay; online JobHunt Help remains available without retaining a conflicting shortcut.
- [ ] #9 Shortcut definitions and displayed help content share a single source of truth where practical, with automated coverage that fails if documented key assignments diverge from registered commands.
- [ ] #10 Focused tests verify job-filter routing, selection-dependent enablement, detail-tab cycling, text-entry suppression for bare ?, Help-menu presentation, overlay dismissal, and representative command execution.
<!-- AC:END -->
