---
id: TASK-391
title: >-
  Docs: Align in-app Help cloud AI privacy copy with actual resume and job text
  transmission
status: Done
assignee: []
created_date: '2026-06-12 23:01'
updated_date: '2026-06-15 04:10'
labels:
  - audit
  - docs
  - privacy
  - help
dependencies: []
references:
  - app/Views/Help/HelpView.swift
  - app/Views/Settings/LLMConsentSheet.swift
  - PRIVACY.md
  - core/LLM/PromptBuilder.swift
modified_files:
  - app/Views/Help/HelpView.swift
priority: high
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
In-app Help currently says only job posting text is sent to cloud AI providers, but fit scoring sends resume text as well. Align Help/About/Troubleshooting copy with the consent sheet, privacy policy, and actual LLM prompt behavior so users understand that cloud or remote providers may receive both job content and resume content.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Help privacy text states that cloud or non-local custom providers may receive job description text and resume text.
- [x] #2 Help copy distinguishes local providers from remote/cloud providers consistently with ConsentHelper.
- [x] #3 The wording matches the consent sheet and external privacy policy.
- [x] #4 A reviewer can trace the documented data flow to the current extraction and fit-scoring code.
<!-- AC:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Updated both in-app Help privacy blocks (the "Local-first" pipeline note and the About-tab "Privacy" note) to state that cloud or non-local custom providers receive job description text AND resume text (resume + job text for fit scoring), and to distinguish local providers (LM Studio/Ollama/loopback custom — nothing leaves the device) from remote ones, consistent with ConsentHelper's loopback-vs-remote logic and the LLMConsentSheet wording ("Job descriptions and resume data … your resume content"). The documented flow traces to ConsentHelper.isConsented gating both extraction and fit-scoring in QueueActor. App target builds clean.
<!-- SECTION:FINAL_SUMMARY:END -->
