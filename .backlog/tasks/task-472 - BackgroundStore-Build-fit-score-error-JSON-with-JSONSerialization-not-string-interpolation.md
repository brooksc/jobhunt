---
id: TASK-472
title: >-
  BackgroundStore: Build fit-score error JSON with JSONSerialization not string
  interpolation
status: To Do
assignee: []
created_date: '2026-06-15 03:39'
labels:
  - bug
  - core
  - llm
dependencies: []
references:
  - core/Models/BackgroundStore.swift
  - core/Models/Projections.swift
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
`markFitScoreFailed` builds error JSON by hand and escapes only double-quotes (BackgroundStore.swift:411-413): `record.fitScoreJSON = "{\"error\":\"\(msg.replacingOccurrences(of: \"\\\"\", with: \"\\\\\\\"\"))\"}"`. An error message containing a backslash, newline, tab, or other control char (common in error.localizedDescription for network/file errors, passed in from QueueActor.swift:720) produces invalid JSON. It is then read back via JSONSerialization in FitScoreProjection.parseJSON (Projections.swift:73-77), which silently returns nil — the failure reason is lost in the UI (no crash). Fix: build the dict with `JSONSerialization.data(withJSONObject: ["error": msg])`.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Fit-score failure JSON is produced via JSONSerialization and is always valid JSON
- [ ] #2 An error message containing quotes/backslashes/newlines round-trips through parseJSON and surfaces in the UI
- [ ] #3 A test covers an error string with control characters
<!-- AC:END -->
