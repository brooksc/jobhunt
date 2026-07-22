---
id: TASK-626
title: 'Prompt AI: Draft a referral request with pasted contact context'
status: Done
assignee: []
created_date: '2026-07-22 21:42'
updated_date: '2026-07-22 22:08'
labels:
  - ai
  - job-detail
  - referral
  - outreach
  - workflow
dependencies:
  - TASK-606
references:
  - TASK-606
  - app/Views/Detail/JobDetailView.swift
  - core/LLM/JobPromptBuilder.swift
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Extend the job-detail Prompt AI menu with a Request Referral action. Before generating, copying, or opening the prompt externally, let the user optionally paste relationship and recipient context, such as a LinkedIn profile, shared history, prior messages, mutual connections, or notes about how they know the person. Append that material at the end of the generated prompt in a clearly delimited Referral Context section. The receiving LLM should draft a concise, credible, low-pressure request for a referral to the selected job, grounded only in the job, resume, fit analysis, and user-supplied context. It must not invent familiarity, endorsements, mutual contacts, or facts about the recipient. Reuse the Prompt AI infrastructure delivered by TASK-606, including resume selection, job-description inclusion, clipboard behavior, external ChatGPT/Claude handling, prompt-injection precautions, and privacy acknowledgement.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 The job-detail Prompt AI menu includes a clearly named Request Referral action distinct from the generic outreach action.
- [ ] #2 Selecting Request Referral presents an optional multiline field where the user can paste LinkedIn profile text, prior conversation, relationship details, mutual connections, or other recipient context.
- [ ] #3 The user-supplied material is appended at the end of the generated prompt inside an explicitly labeled and delimited Referral Context section.
- [ ] #4 When no referral context is supplied, the prompt omits the section cleanly and asks the receiving LLM to produce a suitably cautious cold or weak-connection request.
- [ ] #5 The prompt includes the selected job's company, title, source URL, complete captured job description, selected active resume, and available fit strengths or gaps using the existing TASK-606 selection and formatting behavior.
- [ ] #6 The prompt asks for a concise personalized referral request suitable for the apparent channel, with a clear job link, a brief truthful fit rationale, a specific referral ask, an easy way to decline, and no pressure or exaggerated familiarity.
- [ ] #7 The receiving LLM is instructed not to invent a relationship, mutual connection, recipient knowledge, endorsement, candidate fact, or job fact, and to identify missing personalization details instead.
- [ ] #8 Pasted LinkedIn or conversation text is treated as untrusted reference data and cannot override the prompt's instructions.
- [ ] #9 Referral context is not persisted after the prompt workflow closes unless the user explicitly saves it through an existing notes workflow.
- [ ] #10 Copy and ChatGPT/Claude actions use the same deterministic referral prompt; external-open privacy wording covers the pasted personal context as well as resume and job-description data.
- [ ] #11 Oversized external prompts use the existing full-copy plus blank-chat fallback without truncating the referral context.
- [ ] #12 Focused tests cover context inclusion and omission, end-of-prompt placement, delimiters, non-invention instructions, untrusted-content handling, and reuse of external URL-size fallback behavior.
<!-- AC:END -->
