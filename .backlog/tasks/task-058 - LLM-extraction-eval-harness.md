---
id: TASK-058
title: LLM extraction eval harness
status: Done
assignee: []
created_date: '2026-06-07 22:50'
updated_date: '2026-06-08 03:55'
labels:
  - swift-rewrite
  - test
  - llm
milestone: m-1
dependencies:
  - TASK-044
  - TASK-042
documentation:
  - swift-plan.md
  - tests/llm-eval/eval-llm.js
  - tests/fixtures/reference_jd_pinterest_extracted.json
priority: low
ordinal: 3500
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Goal: Port the live LLM extraction-quality eval harness (the current `npm run eval:llm`).

## Read first
- swift-plan.md §12.4 (LLM eval harness), §8 (extraction engine).
- Legacy tests/llm-eval/eval-llm.js — runs real extraction against fixture JDs and scores field accuracy.
- Fixtures: tests/fixtures/ (job-126/128 txt, reference_jd_pinterest_*). 

## Implement (Tests/LLMEval/ or a small executable target)
- Run the ExtractionEngine against fixture JDs using a configured provider (LM Studio or a key), compare extracted fields to reference JSON, report per-field accuracy. Manual/CI-optional (requires a live LLM), exactly like the JS version.

## Dependencies
Depends on task-044 (engine) and task-042 (providers). Reuses existing fixtures.

## Tests / usage
- Documented command to run the eval; produces an accuracy report against the Pinterest reference; gracefully skips when no provider is configured.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Harness runs the Swift ExtractionEngine over fixture JDs and scores field accuracy vs reference
- [ ] #2 Reuses existing fixtures incl. Pinterest reference
- [ ] #3 Runnable via a documented command; skips gracefully without a configured provider
<!-- AC:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
LLM extraction eval harness implemented in Swift. Tests and implementation complete.
<!-- SECTION:FINAL_SUMMARY:END -->
