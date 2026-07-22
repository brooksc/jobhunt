---
id: TASK-627
title: 'Custom Prompt AI templates with job, resume, and fit variables'
status: To Do
assignee: []
created_date: '2026-07-22 21:48'
labels:
  - ai
  - settings
  - job-detail
  - workflow
  - customization
dependencies:
  - TASK-606
references:
  - TASK-606
  - app/Views/Settings
  - app/Views/Detail/JobDetailView.swift
  - core/LLM/JobPromptBuilder.swift
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Let users create and manage custom AI prompt templates in Settings and expose enabled templates in the job-detail Prompt AI menu as copy actions. Use a simple namespaced `{{variable}}` syntax that is readable in prose and extensible without colliding with Swift interpolation. Initial variables should include `{{job.company}}`, `{{job.title}}`, `{{job.location}}`, `{{job.url}}`, `{{job.description}}`, `{{resume.text}}`, and `{{fit.analysis}}`. Settings should provide an insertion menu so users do not need to memorize token names, validation and preview, and a safe starter template that treats job-description and resume content as reference data. Selecting a custom prompt for a job deterministically resolves its variables and copies the rendered prompt without calling JobHunt's configured AI provider. Reuse the resume-selection and full-description formatting behavior introduced by TASK-606.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Settings includes a Custom AI Prompts section where users can create, name, edit, duplicate, enable or disable, reorder, and delete prompt templates.
- [ ] #2 Custom prompt templates are stored locally and persist across application restarts.
- [ ] #3 Templates use documented namespaced tokens in the form `{{job.company}}`; the initial supported set includes company, title, location, source URL, full formatted job description, selected resume text, and available fit analysis.
- [ ] #4 The template editor provides a variable insertion menu with human-readable labels and descriptions so users do not need to type or memorize token syntax.
- [ ] #5 New templates can start from a useful example that clearly delimits inserted job-description and resume content and tells the receiving LLM to treat that content as untrusted reference data rather than instructions.
- [ ] #6 Settings validates templates before saving, identifies unknown or malformed tokens precisely, and does not silently discard unsupported text.
- [ ] #7 Settings provides a rendered preview using clearly labeled sample values without exposing data from an arbitrary real job.
- [ ] #8 Enabled custom templates appear in a distinct Custom Prompts group in the job-detail Prompt AI menu using their user-defined names and configured order.
- [ ] #9 Selecting a custom prompt resolves variables for the currently displayed job and copies the complete rendered prompt to the clipboard without making a network request or invoking the configured AI provider.
- [ ] #10 Templates that reference `{{resume.text}}` or `{{fit.analysis}}` reuse TASK-606 resume selection and include analysis only for the selected resume.
- [ ] #11 Unavailable values are not silently replaced with empty text; the copy workflow identifies missing variables and either blocks with actionable guidance for required source content or renders an explicit not-available marker for optional metadata.
- [ ] #12 Inserted job descriptions, resumes, and fit analyses preserve useful formatting and are not truncated.
- [ ] #13 Built-in Prompt AI actions remain available and cannot be edited or deleted through the custom-template settings.
- [ ] #14 Custom prompt names and templates have reasonable size limits, and an empty name or empty template cannot be saved.
- [ ] #15 Focused tests cover template persistence, ordering and enablement, token parsing, malformed and unknown tokens, deterministic rendering, missing values, resume and fit resolution, formatting preservation, clipboard-only behavior, and isolation from built-in prompts.
<!-- AC:END -->
