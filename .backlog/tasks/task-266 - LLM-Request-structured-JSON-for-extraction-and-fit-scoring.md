---
id: TASK-266
title: 'LLM: Request structured JSON for extraction and fit scoring'
status: Done
assignee: []
created_date: '2026-06-12 03:25'
updated_date: '2026-06-12 03:30'
labels:
  - audit
  - llm
  - extraction
  - fit-scoring
dependencies: []
references:
  - core/LLM/ExtractionEngine.swift
  - core/LLM/LLMProvider.swift
  - core/LLM/Providers/OpenAICompatibleTransport.swift
priority: high
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Extraction and fit scoring use prompt-only JSON despite the provider layer supporting json_schema/json_object negotiation. Define schemas for extraction and fit outputs, pass responseFormat on ChatRequest where providers support it, and preserve fallback behavior for text-only providers.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Extraction requests pass a structured response format when supported by the selected provider path.
- [ ] #2 Fit scoring requests pass a structured response format when supported by the selected provider path.
- [ ] #3 OpenAI-compatible transport continues to fall back from json_schema to json_object to text on unsupported providers.
- [ ] #4 Tests assert extraction and fit build requests with the intended response format.
<!-- AC:END -->
