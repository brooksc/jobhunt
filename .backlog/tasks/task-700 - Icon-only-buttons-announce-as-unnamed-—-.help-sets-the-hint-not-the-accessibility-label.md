---
id: TASK-700
title: >-
  Icon-only buttons announce as unnamed — .help() sets the hint, not the
  accessibility label
status: To Do
assignee: []
created_date: '2026-08-31 19:27'
labels: []
dependencies: []
priority: high
type: bug
ordinal: 74000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
From the 2026-08-31 accessibility audit (`scratchpad/audit-a11y.md`). Highest-impact finding, and the fix is one line per site.

**The trap:** SwiftUI's `.help("…")` sets the accessibility **hint**, not the **name**. An icon-only `Button { Image(systemName: "trash") }` with only `.help("Remove source")` is announced by VoiceOver as an unnamed button — the tooltip text arrives as supplementary detail *after* the control has already failed to identify itself. It looks correct in code review and in the UI, because sighted users see the tooltip.

The audit counts **~40 icon-only buttons** in this state. (A cruder grep for `.help()` without a nearby `accessibilityLabel` returns 113 sites, but most of those are on controls that already carry a visible text label and are fine — use the audit's narrower list, not that number.)

**The correct pattern already exists in the repo**, at `app/Views/Settings/SearchSettingsTab.swift:530-534`:

```swift
Button(role: .destructive, action: onDelete) {
    Image(systemName: "trash")
}
.buttonStyle(.borderless)
.accessibilityLabel("Remove \(source.label)")
```

Note it names the *specific* thing ("Remove Greenhouse — Acme"), not the generic action ("Delete"). In a list of identical icon buttons a generic label is nearly as useless as none, because VoiceOver users navigate by name.

**Guard it against regression.** This is a pattern that will silently come back with the next icon button. Add an assertion to `AccessibilityAuditTests`, or a lint rule, so a new `.help()` on an icon-only control without a label fails rather than being caught by the next audit.

The audit's other 7 findings (2 high / 3 medium / 3 low) and 5 items needing a running app are in the report; file separately if they're worth doing.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Every icon-only button named in the audit carries an .accessibilityLabel()
- [ ] #2 Labels name the specific target where a list contains repeated icon buttons, matching SearchSettingsTab.swift:534
- [ ] #3 .help() is retained as the hint where it adds detail beyond the label
- [ ] #4 A test or lint rule fails when a new icon-only control ships without a label
<!-- AC:END -->
