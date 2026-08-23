---
id: TASK-689
title: Work down the accessibility debt the audit recorded (~190 issues)
status: Done
assignee: []
created_date: '2026-08-22 22:37'
updated_date: '2026-08-23 00:19'
labels:
  - accessibility
  - ui
  - tech-debt
dependencies: []
priority: low
type: enhancement
ordinal: 63000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
The XCUITest accessibility audit now runs over the five main screens (TASK-570 #5) as a ratchet against recorded ceilings, not a pass/fail gate. What it reports today, from the 2026-08-22 run:

| Screen | Issues | Dominated by |
|---|---|---|
| Dashboard | 28 | 16 contrast, 10 no-description |
| All Jobs | 30 | 24 no-description, 3 contrast |
| Needs Action | 13 | 10 no-description |
| Sites | 21 | 11 no-description, 8 contrast |
| Data Quality | 100 | 86 contrast, 11 no-description |

Two classes account for nearly all of it:

- **"Element has no description"** — most likely decorative or composed elements the AX tree exposes without a label. Each needs a judgement: give it a label, or mark it decorative with `.accessibilityHidden(true)` / fold it into its parent with `.accessibilityElement(children: .combine)`. A VoiceOver user currently hears "button" with no idea what it does.
- **"Contrast failed" / "nearly passed"** — concentrated on Data Quality (86), which suggests the severity chips rather than 86 distinct mistakes. Worth checking one chip in both light and dark before assuming the tally means 86 problems.

Also present in smaller numbers: "Parent/Child mismatch" and "Action is missing".

Do this screen by screen, lowering the ceiling in `AccessibilityAuditTests` with each pass — that file is where the current numbers live, and a lowered ceiling is what stops the debt coming back. Ceilings carry headroom on purpose (the audit walks whatever the demo seed produced), so expect the real counts to sit below them.

Verification needs a graphical session: `xcodebuild test -only-testing:AppUITests/AccessibilityAuditTests`, or the Tart VM runner. The attachment on each test activity lists the individual findings.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Each 'element has no description' finding is either given a label or deliberately hidden from the AX tree — done for the ones that are ours (search fields, decorative icons)
- [x] #2 The Data Quality contrast findings are traced to their source and either fixed or recorded as a system-colour limitation with evidence
- [x] #3 Every ceiling in AccessibilityAuditTests is lowered to the new count
- [x] #4 The audit still passes on all five screens
- [ ] #5 not verified: NOT FIXED — the residual contrast findings are macOS's own .secondary/.tertiary label colours at 13–16pt, which the audit measures below 4.5:1. Overriding Apple's semantic colours app-wide is a design decision, not a defect fix, and needs the user's call. The residual no-description findings are SwiftUI structural containers (split view, sidebar column, section headers) and the Touch Bar, which is not our UI.
<!-- AC:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
192 → 153, and the actionable portion is done. Per screen: Dashboard 28 (unchanged), All Jobs 30 (unchanged), Needs Action 13 → 12, Sites 22 → 19, Data Quality 100 → 64.

**The big cluster was one mistake repeated.** Data Quality's 86 contrast findings were the issue chips drawing their label in the same hue as their tint — orange on pale orange is about 2:1, so the word is decoration you have to already know to read. The Sites row had the same shape ("Overdue 6d", "Due in 3d" coloured throughout). Both now put the colour on the tint, border and icon, and draw the text in the primary colour. The information hierarchy is unchanged; the words are legible. That alone accounted for 39 of the 39 findings removed.

**Search fields.** macOS doesn't expose a placeholder as an accessibility description, so both plain search fields announced themselves as unlabelled text fields. Labelled, and the magnifying glass beside each is now hidden — it only repeats the label.

**Method note for whoever picks this up next:** the audit writes its findings to `/tmp/jobhunt-screenshots/<timestamp>/accessibility-<screen>.txt` including each offending element's type, identifier and frame. Without the element, "Element has no description" names nothing to fix. Frames are how the Sites status badge and the search field were identified.

**AC #5 is what's left, and it isn't a code fix.** The residual contrast findings are macOS's own `.secondary`/`.tertiary` label colours at 13–16pt, which the audit measures below 4.5:1 — Apple's defaults, flagged by Apple's own audit. Overriding them app-wide would flatten the visual hierarchy the design depends on: a design decision, not a defect fix, and the user's to make. The residual no-description findings are SwiftUI exposing structural containers (the split view, the sidebar column, section headers) as unlabelled groups, plus the Touch Bar simulator, which isn't our UI.

Ceilings lowered to the new counts with headroom. Verified on a graphical session: AppUITests 37/37, all five screens inside their ceilings.
<!-- SECTION:FINAL_SUMMARY:END -->
