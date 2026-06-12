---
id: TASK-217
title: >-
  Privacy: Enforce persisted remote-provider consent before fit scoring sends
  resume data
status: Done
assignee: []
created_date: '2026-06-12 01:04'
updated_date: '2026-06-12 02:00'
labels:
  - privacy
  - llm
  - consent
dependencies: []
references:
  - core/LLM/QueueActor.swift
  - core/LLM/ExtractionEngine.swift
  - core/LLM/PromptBuilder.swift
  - core/Settings/ConsentHelper.swift
priority: high
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Fit scoring should check the already-saved consent state immediately before sending job/resume data to the configured provider, matching extraction behavior. This must not prompt on every fit score; it should silently proceed when consent is persisted and fail/block when consent was revoked or never granted.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Fit request processing evaluates persisted consent immediately before calling the LLM provider.
- [ ] #2 A consented provider proceeds without showing a repeat consent prompt.
- [ ] #3 A remote/cloud provider without persisted consent fails or blocks the fit request before resume text is included in a provider request.
- [ ] #4 Extraction and fit consent behavior share the same helper logic where practical.
- [ ] #5 Tests cover consent granted, consent missing, and consent revoked after queueing for fit requests.
<!-- AC:END -->
