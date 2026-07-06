---
id: TASK-602
title: 'fit scoring: dynamic gap penalty (kind×status) + reweight preferred quals up'
status: Done
assignee: []
created_date: '2026-07-06 23:15'
labels:
  - fit-scoring
  - llm
dependencies: []
modified_files:
  - core/Services/FitScorer.swift
  - core/LLM/ExtractionEngine.swift
  - core/LLM/PromptBuilder.swift
  - core/LLM/StructuredOutputSchemas.swift
  - tests/CoreTests/FitScorerTests.swift
  - tests/CoreTests/JobServiceTests.swift
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Real data showed fit scores compressed at the top (26/64 in 90-100) and poorly discriminating: experience_level scored near-constant (~98) while carrying 20% weight, and preferred_qualifications — the dimension that actually varied (avg 79.7, the real signal) — carried only 5% and unmet *preferred* quals weren't differentiated. The old domain-gap penalty was a hardcoded hardware keyword list (asic/fpga/rtl/…) that fired on almost nothing (15/64 jobs had any penalty).

Changes (per user: aggressive preferred treatment + structural per-job gap severity):
- Weights: required .40, preferred .20 (was .05), skills .15, domain .15, experience .10 (was .20). Total 1.0.
- Replaced the domain-gap keyword heuristic with a dynamic kind×status penalty grid: required/missing -12, required/partial -6, preferred/missing -10, preferred/partial -5; cap raised 50→60. Severity now comes from the LLM's per-job judgment (required vs preferred, from the job's own lists) instead of a fixed word list.
- Now penalizes *partial* coverage too (was missing-only).
- LLM prompt + structured schema: each requirement_assessment now carries `kind: required|preferred` (LLM tags it from which job list it came from). ExtractionEngine builds gaps from assessments (partial+missing); rescoreFromJSON reads assessments (legacy strings → missing required gaps; missing kind → defaults required).

Reweight-only preview on the user's 64 scored jobs: full-preferred-coverage jobs float to the top 8; low-preferred jobs drop. Full decompression comes on re-run (the LLM must emit `kind`, and partial penalties then apply) — old stored scores are unchanged until re-scored.</description>
<parameter name="acceptanceCriteria">["dimensionWeights total 1.0 with preferred .20 / experience .10", "penalty from kind×status grid (req/miss 12, req/part 6, pref/miss 10, pref/part 5), cap 60; partials penalized", "LLM schema + prompt require a `kind` (required|preferred) per requirement_assessment; ExtractionEngine + rescoreFromJSON build gaps from assessments", "CoreTests green (FitScorer rewritten + JobServiceTests rescore expectation updated); app builds; lint/format clean"]
<!-- SECTION:DESCRIPTION:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Reweighted fit dimensions (preferred .05→.20, experience .20→.10) and replaced the hardcoded hardware domain-gap keyword list with a dynamic kind×status penalty grid (required/preferred × partial/missing, cap 60) driven by the LLM's per-requirement assessment; added a `kind` tag to the fit schema/prompt so severity is judged per job+resume. Partials are now penalized. CoreTests green (FitScorer tests rewritten, one JobService rescore expectation updated 76→71); app builds; lint/format clean. Existing scores unchanged until re-run (LLM must emit kind).
<!-- SECTION:FINAL_SUMMARY:END -->
