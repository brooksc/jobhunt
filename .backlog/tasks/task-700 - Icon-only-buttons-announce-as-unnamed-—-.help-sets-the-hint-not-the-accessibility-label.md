---
id: TASK-700
title: >-
  Icon-only buttons announce as unnamed — .help() sets the hint, not the
  accessibility label
status: Done
assignee: []
created_date: '2026-08-31 19:27'
updated_date: '2026-09-04 19:52'
labels: []
dependencies: []
priority: high
type: bug
ordinal: 74000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
From the 2026-08-31 accessibility audit (`scratchpad/audit-a11y.md`), with a critical addition from the backlog audit.

**The trap:** SwiftUI's `.help("…")` sets the accessibility **hint**, not the **name**. An icon-only `Button { Image(systemName: "trash") }` with only `.help("Remove source")` is announced by VoiceOver as an unnamed button — the tooltip arrives as supplementary detail *after* the control has already failed to identify itself. It looks correct in review and on screen, because sighted users see the tooltip.

The audit counts **~40 icon-only buttons** in this state. (A cruder grep for `.help()` without a nearby label returns 113 sites, but most are on controls that already carry visible text and are fine — use the audit's narrower list. `app/` overall has ~120 `.help(` against ~28 `.accessibilityLabel(`.)

## Fix the CI check FIRST — it enforces the wrong invariant

`scripts/check-tooltips.sh` shipped under [[TASK-494]] and runs in CI (`.github/workflows/swift-build.yml:134`). **Verified:** line 37 accepts *either* token —

    if any(token in modifier_block for token in (".help(", ".accessibilityLabel(")):

— so an icon-only control with `.help()` and no label passes. Worse, line 44 tells the developer what to do about a failure:

    "Add .help(\"…\") describing the action."

CI has therefore been *teaching* the wrong remedy since TASK-494 landed. That is plausibly why 120 `.help(` accumulated against 28 labels: people did what the check told them.

**A guard enforcing the wrong invariant is worse than no guard** — it creates false confidence and actively points the fix in the wrong direction. Fix the ~40 buttons without changing this script and CI will re-approve the next regression while sending the next person back to `.help()`.

So: require `.accessibilityLabel(` for an icon-only control, treat `.help(` as optional supplementary detail, and rewrite the failure message accordingly.

## The correct pattern already exists in the repo

`app/Views/Settings/SearchSettingsTab.swift:530-534`:

    Button(role: .destructive, action: onDelete) {
        Image(systemName: "trash")
    }
    .buttonStyle(.borderless)
    .accessibilityLabel("Remove \(source.label)")

It names the *specific* target ("Remove Greenhouse — Acme"), not the generic action. In a list of identical trash icons a generic label is nearly as useless as none, because VoiceOver users navigate by name.

The audit's other 7 findings (2 high / 3 medium / 3 low) and 5 items needing a running app are in the report; file separately if worth doing.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 scripts/check-tooltips.sh requires .accessibilityLabel( for icon-only controls and no longer accepts .help( alone
- [ ] #2 Its failure message directs the developer to add a label, not a tooltip
- [ ] #3 Every icon-only button named in the audit carries an .accessibilityLabel()
- [ ] #4 Labels name the specific target where a list contains repeated icon buttons, matching SearchSettingsTab.swift:534
- [ ] #5 .help() is retained as the hint where it adds detail beyond the label
- [ ] #6 The corrected check passes in CI and would fail on a newly added unlabeled icon control
<!-- AC:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Fixed in 3f61cbc7 (merged via a6d519e4). `scripts/check-tooltips.sh` previously accepted `.help(` OR `.accessibilityLabel(` and told developers to add `.help("…")` — but `.help()` sets the accessibility *hint*, not the *name*, so CI had been teaching the wrong remedy since TASK-494. The script now requires `.accessibilityLabel(` on icon-only controls and treats `.help(` as supplementary. It then found 32 unlabelled icon-only sites across 15 files, all now labelled.

Status corrected 2026-09-04 — the work landed 2026-09-03. Verified in the code (61 `.accessibilityLabel(` call sites in `app/`), not from the commit message.
<!-- SECTION:FINAL_SUMMARY:END -->
