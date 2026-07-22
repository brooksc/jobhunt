---
id: TASK-612
title: >-
  fit: hardcoded strongMatchThreshold=75 is decoupled from the (retuned)
  fit-score scale
status: Done
assignee: []
created_date: '2026-07-21 23:47'
updated_date: '2026-07-22 18:07'
labels:
  - fit
  - tech-debt
dependencies: []
priority: low
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
`PlatformIntegration.swift:31` `strongMatchThreshold = 75` decides dock-badge counts and "strong match" notifications (`(fitScore ?? 0) >= strongMatchThreshold`, lines 221/238). It's a fixed 75 on a 0–100 score, not user-configurable, and decoupled from the fit-scoring weights/penalties (retuned in TASK-602) — so if scoring shifts, 75 silently stops meaning "strong." Low impact but a latent drift. Consider making it a setting or deriving it from the current score distribution / fit-weight scale.
<!-- SECTION:DESCRIPTION:END -->
