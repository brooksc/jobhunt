---
id: TASK-321
title: 'LLM providers: Honor configured provider model consistently'
status: Done
assignee: []
created_date: '2026-06-12 20:01'
updated_date: '2026-06-12 20:18'
labels:
  - audit
  - llm-provider
  - settings
dependencies: []
references:
  - core/LLM/Providers/OpenAIProvider.swift
  - core/LLM/Providers/OpenAICompatibleTransport.swift
  - core/LLM/LLMProviderFactory.swift
priority: high
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Provider classes store a configured model, but complete(_:) sends ChatRequest.model. The factory passes configured models into providers, but providers do not enforce or default to those models, making direct provider usage and snapshot drift easier.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Define whether ChatRequest.model or provider configuration is the source of truth for model selection.
- [ ] #2 Provider implementations consistently use the chosen model source and tests assert request body/URL model selection.
- [ ] #3 Connection tests and queue processing use the same model-selection path.
<!-- AC:END -->
