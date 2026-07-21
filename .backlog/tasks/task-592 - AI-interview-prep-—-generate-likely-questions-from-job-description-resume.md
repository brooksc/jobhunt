---
id: TASK-592
title: 'AI: interview prep — generate likely questions from job description + resume'
status: To Do
assignee: []
created_date: '2026-07-02 21:52'
updated_date: '2026-07-21 22:59'
labels: []
dependencies:
  - TASK-501
references:
  - core/LLM/QueueActor.swift
  - core/LLM/PromptBuilder.swift
  - core/LLM/StructuredOutputSchemas.swift
  - app/Views/Detail/JobDetailView.swift
  - core/Models/Enums.swift
priority: low
ordinal: 41000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
**Opportunity:** The app has the job description (extracted), the user's resume (stored as PDF text), the fit score (gap analysis), and a full LLM queue pipeline. Generating likely interview questions per job is the highest-leverage new use of the existing infrastructure.

**How to implement:**
1. Add `LLMRequestType.interviewPrep` to `core/Models/Enums.swift`.
2. Add `PromptBuilder.buildInterviewPrepPrompt(job:resume:fitScore:)` — input: extracted job requirements + skills gap from fit score + resume text. Output: structured JSON with `{ "behavioral": [...], "technical": [...], "role_specific": [...] }`.
3. Add `StructuredOutputSchemas.interviewPrep` (matches the above JSON shape).
4. Wire into `QueueActor` following the existing fit-score request pattern (enqueue, process, persist result to job).
5. Persist the result in a new `interviewPrepJSON` field on `Job` (or a separate `InterviewPrep` model if questions need to be individually checked off).
6. Add a new "Prep" tab in `JobDetailView` — lists questions by category with a checkbox to mark each as practiced.

**Dependencies:** Requires an active resume and a completed extraction. Gate enqueue on both (same guard as fit scoring).

**Scope:** ~300–400 lines across model, queue, prompt, and UI. Non-trivial but all infrastructure exists.

**Parked — good candidate after the core workflow is stable.** Consider implementing after TASK-501 (structured interview/offer tracking) since they're adjacent in the job-detail tabs.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 'Prep' tab appears in job detail when extraction + active resume exist
- [ ] #2 Tapping 'Generate Prep Questions' enqueues an interviewPrep LLM request
- [ ] #3 Questions appear in three categories: behavioral, technical, role-specific
- [ ] #4 Each question has a checkbox; checked state persists across launches
- [ ] #5 Re-generating replaces the previous set with a confirmation prompt
<!-- AC:END -->
