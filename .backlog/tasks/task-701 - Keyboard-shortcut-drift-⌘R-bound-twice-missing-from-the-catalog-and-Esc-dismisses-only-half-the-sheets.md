---
id: TASK-701
title: >-
  Keyboard shortcut drift: ⌘R bound twice, missing from the catalog, and Esc
  dismisses only half the sheets
status: To Do
assignee: []
created_date: '2026-08-31 19:27'
labels: []
dependencies: []
priority: medium
type: bug
ordinal: 75000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
From the 2026-08-31 accessibility audit (`scratchpad/audit-a11y.md`, Part 2). These are concrete defects in shortcuts that already ship — distinct from [[TASK-698]], which is the open design discussion about navigation and should not be blocked on these.

**⌘R is bound twice** (verified):
- `app/Shell/AppCommands.swift:73` — global menu command
- `app/Views/Quality/DataQualityView.swift:326` — view-local

So what ⌘R does depends on which view is showing, and a view-local binding shadows the menu command with no indication in the menu that it has been overridden. Decide which owns it; if both genuinely need a refresh action, give the view-local one its own chord.

(`AppCommands.swift:129` also binds ⌃⌘R — a distinct chord, not a conflict, but worth confirming it's intentional alongside the other two.)

**⌘R is missing from `KeyboardShortcutCatalog`.** [[TASK-499]] shipped an in-app shortcut reference; a binding absent from it is invisible to the user and to whoever adds the next shortcut, which is how the double-binding survived. The catalog needs to be the single source of truth, and ideally a test should assert every `.keyboardShortcut` in the tree appears in it — otherwise this drifts again.

**Esc dismisses only about half the sheets.** Inconsistent dismissal is worse than none: the user learns Esc works, tries it on a sheet that ignores it, and is stuck reaching for a mouse in a modal. Audit every sheet and make it uniform.

The audit's full inventory — 23 bindings across menus, the `NSEvent` monitor and view-local handlers, per-surface reachability, 11 mouse-required gaps and 6 conflict/shadowing notes — is in the report and feeds [[TASK-698]].
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 ⌘R has exactly one owner; any second refresh action uses a different chord
- [ ] #2 Every .keyboardShortcut in the tree appears in KeyboardShortcutCatalog, asserted by a test
- [ ] #3 Esc dismisses every sheet, or the exceptions are deliberate and documented
- [ ] #4 The 6 conflict/shadowing notes from the audit each have a decision
<!-- AC:END -->
