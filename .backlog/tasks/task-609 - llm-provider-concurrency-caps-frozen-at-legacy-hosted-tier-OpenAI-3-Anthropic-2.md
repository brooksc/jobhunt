---
id: TASK-609
title: >-
  llm: provider concurrency caps frozen at legacy hosted tier (OpenAI 3 /
  Anthropic 2)
status: To Do
assignee: []
created_date: '2026-07-21 23:40'
labels:
  - llm
  - performance
  - tech-debt
dependencies: []
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
`OpenAIProvider.swift:4,7` sets `concurrencyLimit = 3` "to mirror legacy HOSTED_CONCURRENCY" and `AnthropicProvider.swift:15` sets `2`. These are copied from the decommissioned JS hosted server's tier and are the ceiling for `AdaptiveConcurrency` (which only backs OFF, never above the ceiling — `AdaptiveConcurrency.swift:6`). Modern paid API tiers (the user's own key) permit far higher throughput, so batch extraction/scoring is needlessly serialized during bulk imports.

Needs care (don't just crank it): higher concurrency risks 429s. Consider making the ceiling a setting, or raising defaults with the adaptive back-off (+ Retry-After handling, see the retry-after clamp fix) doing the safety work. Validate against real provider rate limits.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Concurrency ceiling reflects modern API tiers (configurable and/or higher default), not the dead hosted server's 3/2
- [ ] #2 Adaptive back-off + Retry-After still protect against sustained 429s at the higher ceiling
<!-- AC:END -->
