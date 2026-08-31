---
id: TASK-698
title: 'Design discussion: full keyboard navigation across the app'
status: To Do
assignee: []
created_date: '2026-08-31 19:21'
labels: []
dependencies: []
priority: medium
type: spike
ordinal: 72000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Raised by the user 2026-08-31. Wants to discuss how to improve keyboard navigation across the whole app — a direction conversation, **not** a task to implement blind.

The distinction that matters: [[TASK-499]] ("Comprehensive keyboard shortcuts and in-app shortcut reference") is Done, so **shortcuts** largely exist. The open question is **navigation** — whether the app can be driven end-to-end without a mouse: focus order, Tab traversal, where focus lands when a sheet opens and closes, whether Esc dismisses consistently, and which controls are click-only today.

**Input for the discussion:** the `audit-a11y` pass (2026-08-31) produced a factual inventory rather than a proposal — every shortcut and where it's defined, which surfaces are keyboard-reachable, focus behaviour per sheet, named gaps where a mouse is required, conflicts with standard macOS shortcuts, and a comparison against the conventions a Mac user expects (⌘F focus search, ⌘1..n tab switching, ⌥⌘←/→ navigation, Space to preview, Return to open). See `scratchpad/audit-a11y.md` Part 2. That inventory is the starting point.

Do not start implementing before the discussion — the choice of navigation model (focus-ring traversal vs. vim-style keys vs. leaning on macOS defaults) shapes everything downstream, and picking it unilaterally would be the expensive kind of wrong.

Related: accessibility findings from the same audit are separate; keyboard-only operation and VoiceOver support overlap but are not the same goal.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 A navigation model is chosen and written down, with the tradeoffs that decided it
- [ ] #2 The click-only surfaces named in the audit each have a decision: reachable, or deliberately not
- [ ] #3 Implementation work is broken into separate tasks once the direction is agreed
<!-- AC:END -->
