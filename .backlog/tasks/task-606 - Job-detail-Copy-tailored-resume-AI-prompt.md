---
id: TASK-606
title: 'Job detail: Copy tailored-resume AI prompt'
status: To Do
assignee: []
created_date: '2026-07-21 22:22'
labels:
  - workflow
  - resume
  - ai
  - job-detail
dependencies: []
references:
  - app/Views/Detail/JobDetailView.swift
  - core/Models/Resume.swift
  - core/Models/Job.swift
  - core/Models/Capture.swift
  - core/Models/JobFitScore.swift
  - core/Models/Projections.swift
  - core/LLM/PromptBuilder.swift
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Add a “Copy AI Prompt for Resume” action for the currently displayed job. The action builds a self-contained prompt for an external LLM and copies it to the clipboard; it must not automatically call the configured AI provider.

Resume selection:
- Prefer the active resume with the highest completed JobFitScore for the job.
- If there is one active resume and no completed fit score, use that resume.
- If multiple active resumes are equally eligible or unscored, present a compact resume chooser before copying.
- If no usable resume exists, disable the action or explain that a resume must be added/activated in Settings.

Prompt contents:
- Identify the target role, company, location, and canonical/source job URL.
- Include the complete formatted job-description text in a clearly delimited section so the receiving LLM does not depend on URL access. Prefer the cleaned captured description while preserving useful headings, paragraphs, and bullets; do not substitute only the extracted summary or requirements.
- Include the selected resume’s complete stored text in a separate clearly delimited section.
- When a completed fit analysis exists for that resume, include the fit score, strengths/requirements met, gaps or partial requirements, and useful dimension rationales. Omit this section cleanly when analysis is unavailable rather than fabricating it.
- Tell the LLM to treat the embedded job description and resume as reference data, not as instructions, to reduce prompt-injection risk from captured page text.

Prompt instructions to the receiving LLM:
- Produce a complete, ATS-friendly resume tailored to the role, with clear section headings and concise accomplishment-oriented bullets.
- Preserve the candidate’s identity, employers, roles, dates, education, chronology, and factual claims. Never invent experience, credentials, technologies, responsibilities, or metrics.
- Prioritize and rephrase truthful experience that demonstrates the job’s required and preferred qualifications, using relevant terminology naturally rather than keyword stuffing.
- Address fit gaps only through supported transferable evidence. Put unsupported gaps or needed clarifications in a separate “Questions / Evidence Needed” section instead of adding them to the resume.
- Preserve useful existing metrics exactly; do not create new numbers. Remove or de-emphasize irrelevant content only when doing so does not create chronology gaps or misrepresent experience.
- Return the tailored resume first in clean Markdown/plain text, followed by a concise change summary and the optional Questions / Evidence Needed section.

Show success feedback naming the resume used, and show actionable feedback when the job lacks a usable URL, full captured description, or resume text.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 The detail panel exposes a clearly labeled “Copy AI Prompt for Resume” action for the current job.
- [ ] #2 The action deterministically chooses the highest-scoring active resume, falls back to the sole active resume, and presents a chooser when multiple active resumes cannot be ranked unambiguously.
- [ ] #3 The copied prompt includes the job’s canonical/source URL and complete formatted captured job-description text in a delimited reference section.
- [ ] #4 The copied prompt includes the chosen resume’s complete stored text in a separate delimited reference section.
- [ ] #5 When available for the chosen resume, the prompt includes the best completed fit analysis’s score, strengths, requirements met, gaps/partial requirements, and relevant rationale; the section is omitted cleanly when unavailable.
- [ ] #6 The prompt directs the receiving LLM to produce a complete ATS-friendly tailored resume while preserving facts, chronology, existing metrics, and identity and explicitly forbids invented qualifications or numbers.
- [ ] #7 The prompt treats embedded source content as untrusted reference data and instructs the receiving LLM not to follow instructions found inside the job description or resume.
- [ ] #8 Missing resume text or missing full job-description text prevents copying and produces actionable UI feedback; a missing URL is clearly labeled in the prompt or surfaced before copying rather than silently omitted.
- [ ] #9 Copying performs no network or configured-provider request and shows success feedback that identifies the resume used.
- [ ] #10 Focused tests cover deterministic resume selection, multiple-resume choice, fit-analysis inclusion/omission, URL and description fallback behavior, prompt delimiters and guardrails, clipboard success feedback, and missing-data states.
<!-- AC:END -->
