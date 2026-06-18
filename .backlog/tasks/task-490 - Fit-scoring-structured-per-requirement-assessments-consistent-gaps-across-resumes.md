---
id: TASK-490
title: >-
  Fit scoring: structured per-requirement assessments (consistent gaps across
  resumes)
status: Done
assignee: []
created_date: '2026-06-18 19:07'
updated_date: '2026-06-18 19:07'
labels:
  - llm
  - fit-scoring
  - ux
dependencies: []
priority: high
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
The fit "Not met" list was inconsistent across resumes scored against the same job: each resume is a separate LLM call, and the prompt asked for free-form requirements_met/requirements_not_met arrays, so the model selectively surfaced different gaps per resume (e.g. flagging "executive-facing dashboards" as missing for one resume but not another, even though it was absent from both). Since the user picks which resume to submit based on this, the gaps must be consistent.

Root cause confirmed: requirements ARE extracted once during extraction (job_extraction.requirements/nice_to_haves) and the same list is fed into every resume's fit call — so the input was already consistent; only the free-form output selection varied.

Fix (Option B): replace the free-form met/not-met arrays with a structured `requirement_assessments` array — one object per listed qualification with status (met/partial/missing) + evidence — and instruct the LLM to assess EVERY listed qualification exhaustively. Every resume is now evaluated against the identical requirement set, so gaps are consistent.

Touches: StructuredOutputSchemas (fit schema), PromptBuilder (fit prompt), ExtractionEngine.scoreFit (derive not-met from assessments for the penalty), FitScoreProjection (parse assessments + derive met/not-met for back-compat), JobDetailView (render met / partial / missing with evidence), MockLLMResponder (new shape). Back-compatible: legacy fit scores without assessments still render via the old met/not-met arrays.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Fit schema returns requirement_assessments: [{requirement, status(met/partial/missing), evidence}] instead of free-form met/not-met arrays
- [x] #2 The prompt instructs an exhaustive assessment of every extracted required + preferred qualification, so the same requirements are evaluated for every resume
- [x] #3 FitScoreProjection parses assessments and derives met/not-met (met vs partial+missing); legacy scores still read the old arrays
- [x] #4 The Fit UI shows each requirement with a met/partial/missing status and evidence
- [x] #5 The domain-gap penalty still works (not-met derived from 'missing' assessments)
- [ ] #6 Live-verify with a real key that gaps are now consistent across resumes for the same job
<!-- AC:END -->



## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Replaced the fit scoring's free-form requirements_met/requirements_not_met arrays with a structured, exhaustive per-requirement assessment so the gaps are consistent across every resume scored against a job.

- Job requirements are already extracted ONCE during extraction (job_extraction.requirements/nice_to_haves) and the same list feeds every resume's fit call — so the inconsistency was purely the LLM selectively choosing which gaps to surface in free-form output.
- Schema (StructuredOutputSchemas.fitScore): `requirement_assessments: [{requirement, status: enum(met|partial|missing), evidence}]` replaces the two free-form arrays.
- Prompt (PromptBuilder.fitUserPrompt): instructs the model to assess EVERY listed required + preferred qualification (one object each, no skipping/merging/inventing), noting the list is identical for every candidate.
- ExtractionEngine.scoreFit derives the not-met list (which feeds the domain-gap penalty) from the "missing" assessments, falling back to the legacy array.
- FitScoreProjection parses `requirement_assessments` and derives requirementsMet/requirementsNotMet (met vs partial+missing); legacy fit scores still read the old arrays, so existing data renders unchanged.
- JobDetailView renders each requirement with a met (green ✓) / partial (amber !) / missing (red ✗) icon + evidence subtext; falls back to the old two-column layout for legacy scores.
- MockLLMResponder returns the new shape.

Tests: StructuredOutputSchemasTests (new schema shape + status enum), ProjectionsTests (assessment parse + derived splits), and the existing MockLLM/Google suites all green; full fast gate green; app builds.

AC#6 pending: needs a live re-score (#133) against a real key to confirm the model now flags gaps consistently across resumes — recommend the user re-run with their Gemini key. Note: existing stored fit scores keep the old shape until re-scored; they render via the back-compat path.
<!-- SECTION:FINAL_SUMMARY:END -->
