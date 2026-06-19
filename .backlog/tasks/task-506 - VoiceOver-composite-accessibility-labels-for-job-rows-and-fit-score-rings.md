---
id: TASK-506
title: 'VoiceOver: composite accessibility labels for job rows and fit-score rings'
status: To Do
assignee: []
created_date: '2026-06-19 01:12'
labels:
  - hig
  - accessibility
dependencies: []
priority: medium
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
- [ ] #1 FitRingView/FitPillView expose an accessibilityLabel including the numeric score and the qualitative band
- [ ] #2 A job row is a single VoiceOver element read as one sentence (title, company, location, salary, fit, status)
- [ ] #3 Requirement met/partial/missing states have a non-color cue (symbol or text) and an accessibility label
- [ ] #4 Fit-score band thresholds are shared between the color and the spoken label
<!-- AC:END -->
