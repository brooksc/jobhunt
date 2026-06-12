---
id: TASK-391
title: >-
  Docs: Align in-app Help cloud AI privacy copy with actual resume and job text
  transmission
status: To Do
assignee: []
created_date: '2026-06-12 23:01'
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
priority: high
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
In-app Help currently says only job posting text is sent to cloud AI providers, but fit scoring sends resume text as well. Align Help/About/Troubleshooting copy with the consent sheet, privacy policy, and actual LLM prompt behavior so users understand that cloud or remote providers may receive both job content and resume content.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Help privacy text states that cloud or non-local custom providers may receive job description text and resume text.
- [ ] #2 Help copy distinguishes local providers from remote/cloud providers consistently with ConsentHelper.
- [ ] #3 The wording matches the consent sheet and external privacy policy.
- [ ] #4 A reviewer can trace the documented data flow to the current extraction and fit-scoring code.
<!-- AC:END -->
