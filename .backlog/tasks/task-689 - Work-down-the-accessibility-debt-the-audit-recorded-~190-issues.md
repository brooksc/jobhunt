---
id: TASK-689
title: Work down the accessibility debt the audit recorded (~190 issues)
status: To Do
assignee: []
created_date: '2026-08-22 22:37'
updated_date: '2026-08-22 22:37'
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
- [ ] #1 Each 'element has no description' finding is either given a label or deliberately hidden from the AX tree
- [ ] #2 The Data Quality contrast findings are traced to their source and either fixed or recorded as a system-colour limitation with evidence
- [ ] #3 Every ceiling in AccessibilityAuditTests is lowered to the new count
- [ ] #4 The audit still passes on all five screens
<!-- AC:END -->
