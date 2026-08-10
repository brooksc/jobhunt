---
id: TASK-506
title: 'VoiceOver: composite accessibility labels for job rows and fit-score rings'
status: Done
assignee: []
created_date: '2026-06-19 01:12'
updated_date: '2026-08-10 01:00'
labels:
  - hig
  - accessibility
dependencies: []
modified_files:
  - core/Services/FitBand.swift
  - core/Services/JobRowAccessibility.swift
  - app/Views/Components/FitRingView.swift
  - app/Views/Jobs/JobsView.swift
  - tests/CoreTests/AccessibilityLabelTests.swift
priority: medium
ordinal: 6000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
macOS HIG (5.4/12.1/12.2): information conveyed by color must have a text/symbolic alternative, and composite rows should read as one natural sentence. Today the fit score is shown as a colored ring with a number but no accessibility label, and `JobListRow` exposes only an `accessibilityIdentifier` (for tests), not a user-facing label — so VoiceOver reads disconnected fragments and never speaks the qualitative fit ("Strong fit").

Work:
- FitRingView / FitPillView: add `.accessibilityLabel`/`.accessibilityValue` e.g. "Fit score 88, strong fit" using the same thresholds the color uses.
- JobListRow: wrap as a single accessibility element with a composed label: "{title}, {company}, {location}, {salary}, {fit}, status {status}".
- Requirement status boxes in JobDetailView (met/partial/missing) get text or symbol + a11y label, not color alone.

Evidence: FitRingView.swift (no accessibility modifiers), JobsView.swift:802 (JobListRow), JobDetailView.swift:187-252 (requirementStatusColor color-only).
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 FitRingView/FitPillView expose an accessibilityLabel including the numeric score and the qualitative band
- [x] #2 A job row is a single VoiceOver element read as one sentence (title, company, location, salary, fit, status)
- [x] #3 Requirement met/partial/missing states have a non-color cue (symbol or text) and an accessibility label
- [x] #4 Fit-score band thresholds are shared between the color and the spoken label
<!-- AC:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
#4 turned out to be the root of the others. The band thresholds existed in **three** copies — `FitRingView.color`, `FitPillView.color`, `FitPillView.label` — so the colour a sighted user sees and the word VoiceOver speaks could disagree the moment one moved. They now come from one `FitBand` in Core; the view supplies only the colour mapping.

#1 Ring and pill both announce score *and* band: "Fit score 88 out of 100, Strong fit". Both, because the number alone means nothing without the scale and the band alone loses 55-vs-69. An unscored ring says "Not yet scored for fit" rather than reading as zero — a bad score and a missing one are different situations.

#2 `JobRowAccessibility.label(...)` composes one sentence and the row becomes a single element. Left alone, VoiceOver walked ring, title, company, location, remote tag, status chip and unread dot separately, several of which announce as "circle". Order is deliberate: role and fit first (what you scan a list for), bookkeeping after, unread last. **Judgement call:** salary is spoken even though the row doesn't display it — a VoiceOver user navigates row by row and salary is a thing you filter on, so it's cheap to say and expensive to go hunting for.

#3 **Already shipped — verified, not rewritten.** The icons are distinct *shapes* (checkmark / exclamationmark / xmark), so the state survives greyscale, and the row already carried `.accessibilityElement(children: .combine)` with an explanation spelling out met/partial/missing *and* required/preferred. I added a redundant helper, noticed it duplicated existing behaviour, and removed it. `RequirementVerdictDisplay` in Core now pins the symbol-distinctness and label wording under test.

15 tests. Gate: fast gate TEST SUCCEEDED, BUILD SUCCEEDED, swiftlint 0 violations in 349 files, swiftformat 0.61.1 clean.

not verified: (visual/auditory) — no VoiceOver session was run; that needs the screen and a live desktop. The composed strings, band boundaries and symbol distinctness are unit-tested.
<!-- SECTION:FINAL_SUMMARY:END -->
