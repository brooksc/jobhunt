---
id: TASK-178
title: >-
  Settings: Wire preferred metros into extraction/location logic or remove the
  setting
status: Done
assignee: []
created_date: '2026-06-11 22:13'
updated_date: '2026-06-11 22:30'
labels:
  - audit
  - settings
  - location
  - llm
dependencies: []
references:
  - app/Views/Settings/SettingsTab.swift
  - core/Settings/SettingsStore.swift
  - core/LLM/ExtractionEngine.swift
  - core/LLM/Normalization.swift
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
The settings UI stores `preferredMetros`, but `ExtractionSettings` carries only `preferredLocations`, and extraction/normalization code reads only preferred locations. Wire preferred metros into the location context and salary/location normalization rules, or remove the UI field to avoid advertising unused behavior.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Preferred metros affect extraction/normalization behavior, or the setting is removed from the UI and model defaults.
- [ ] #2 The behavior is documented by code-level tests with at least one metro-specific example.
- [ ] #3 Settings snapshot tests cover the chosen preferred-metros behavior.
<!-- AC:END -->
