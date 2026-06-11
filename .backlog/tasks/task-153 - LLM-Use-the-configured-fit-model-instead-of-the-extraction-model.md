---
id: TASK-153
title: 'LLM: Use the configured fit model instead of the extraction model'
status: To Do
assignee: []
created_date: '2026-06-11 19:31'
labels:
  - llm
  - fit-scoring
  - settings
  - bug
dependencies: []
references:
  - core/LLM/ExtractionEngine.swift
  - core/LLM/QueueActor.swift
  - core/Settings/SettingsStore.swift
priority: high
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
LLM/extraction audit finding: `ExtractionEngine.scoreFit` builds `ChatRequest` with `job.extractionModel ?? ""`. This couples fit scoring to the model that happened to perform extraction and can send an empty model for manually created or unextracted jobs.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Fit scoring receives the current configured model, or a dedicated fit-scoring model setting if product chooses to split extraction and fit models.
- [ ] #2 Manually created or unextracted jobs never send an empty model string to providers during fit scoring.
- [ ] #3 Attempt/request metadata records the requested and returned fit-scoring model clearly.
- [ ] #4 Tests prove fit scoring uses the current settings model rather than `job.extractionModel`.
<!-- AC:END -->
