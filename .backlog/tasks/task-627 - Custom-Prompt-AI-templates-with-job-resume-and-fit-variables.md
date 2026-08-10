---
id: TASK-627
title: 'Custom Prompt AI templates with job, resume, and fit variables'
status: Done
assignee: []
created_date: '2026-07-22 21:48'
updated_date: '2026-08-10 01:22'
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
modified_files:
  - core/Services/PromptTemplate.swift
  - core/Services/PromptTemplateRenderer.swift
  - core/Models/Setting.swift
  - core/Settings/SettingsStore.swift
  - app/Views/Settings/CustomPromptsSettings.swift
  - app/Views/Settings/SettingsTab.swift
  - app/Views/Detail/JobPromptMenu.swift
  - tests/CoreTests/PromptTemplateTests.swift
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Let users create and manage custom AI prompt templates in Settings and expose enabled templates in the job-detail Prompt AI menu as copy actions. Use a simple namespaced `{{variable}}` syntax that is readable in prose and extensible without colliding with Swift interpolation. Initial variables should include `{{job.company}}`, `{{job.title}}`, `{{job.location}}`, `{{job.url}}`, `{{job.description}}`, `{{resume.text}}`, and `{{fit.analysis}}`. Settings should provide an insertion menu so users do not need to memorize token names, validation and preview, and a safe starter template that treats job-description and resume content as reference data. Selecting a custom prompt for a job deterministically resolves its variables and copies the rendered prompt without calling JobHunt's configured AI provider. Reuse the resume-selection and full-description formatting behavior introduced by TASK-606.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Settings includes a Custom AI Prompts section where users can create, name, edit, duplicate, enable or disable, reorder, and delete prompt templates.
- [x] #2 Custom prompt templates are stored locally and persist across application restarts.
- [x] #3 Templates use documented namespaced tokens in the form `{{job.company}}`; the initial supported set includes company, title, location, source URL, full formatted job description, selected resume text, and available fit analysis.
- [x] #4 The template editor provides a variable insertion menu with human-readable labels and descriptions so users do not need to type or memorize token syntax.
- [x] #5 New templates can start from a useful example that clearly delimits inserted job-description and resume content and tells the receiving LLM to treat that content as untrusted reference data rather than instructions.
- [x] #6 Settings validates templates before saving, identifies unknown or malformed tokens precisely, and does not silently discard unsupported text.
- [x] #7 Settings provides a rendered preview using clearly labeled sample values without exposing data from an arbitrary real job.
- [x] #8 Enabled custom templates appear in a distinct Custom Prompts group in the job-detail Prompt AI menu using their user-defined names and configured order.
- [x] #9 Selecting a custom prompt resolves variables for the currently displayed job and copies the complete rendered prompt to the clipboard without making a network request or invoking the configured AI provider.
- [x] #10 Templates that reference `{{resume.text}}` or `{{fit.analysis}}` reuse TASK-606 resume selection and include analysis only for the selected resume.
- [x] #11 Unavailable values are not silently replaced with empty text; the copy workflow identifies missing variables and either blocks with actionable guidance for required source content or renders an explicit not-available marker for optional metadata.
- [x] #12 Inserted job descriptions, resumes, and fit analyses preserve useful formatting and are not truncated.
- [x] #13 Built-in Prompt AI actions remain available and cannot be edited or deleted through the custom-template settings.
- [x] #14 Custom prompt names and templates have reasonable size limits, and an empty name or empty template cannot be saved.
- [x] #15 Focused tests cover template persistence, ordering and enablement, token parsing, malformed and unknown tokens, deterministic rendering, missing values, resume and fit resolution, formatting preservation, clipboard-only behavior, and isolation from built-in prompts.
<!-- AC:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
All 15 criteria implemented. `PromptTemplate` + `PromptTemplateRenderer` in Core hold the parsing, validation and rendering; `CustomPromptsSettings` is the Settings section and editor; the job's Prompt AI menu grows a Custom Prompts group.

**#1/#2** Create, name, edit, duplicate, enable/disable, reorder and delete, stored as JSON in one setting like `ScoringFeedback` — no schema migration. Reordering renumbers densely so a later insert can't collide, and a new prompt appends rather than jumping to the top.

**#3/#4** Seven namespaced tokens; the Insert Variable menu lists each with a label and a description, so nobody types token syntax.

**#5** New prompts start from a template that fences quoted content in `====` markers and tells the receiving model to treat it as reference data, never instructions. Not decoration: a job description is text from a stranger's website and can contain something shaped like a command, and whatever the user pastes it into has no idea which part came from us.

**#6** Every problem reported at once; unknown tokens named precisely; an unterminated `{{` is an error rather than silently swallowing the rest of the template. At *render* time unknown tokens survive verbatim — validation already blocks the save, and eating the user's text would be worse.

**#7** Preview uses obviously-fake sample values. Real job data in a settings preview is a privacy leak waiting to happen, and an 8 KB description makes the sample unreadable.

**#8/#13** Custom prompts sit in their own `Section("Custom Prompts")` in menu order. Built-ins are untouched, live in a different type, and can't be reached from this settings section.

**#9** Renders and copies. No provider call, no network.

**#10** Résumé and fit analysis come from `usableResume` — the same selection the built-in prompts use — so a custom prompt can't quietly score against a different résumé than the rest of the screen.

**#11** Two directions, deliberately. A template needing `{{job.description}}` or `{{resume.text}}` that can't have one is **refused** with the missing names, because copying a prompt with a "[not available]" hole wastes a round trip through whatever it's pasted into. Optional gaps render an explicit marker and are named in the toast — an empty substitution would leave the model reading "the role at  in " and inferring something from the gap.

**#12** The description is substituted verbatim; a test pins that internal blank lines survive and a 25 KB body isn't truncated.

**#14** 60-character names, 20 000-character bodies, empty name or body unsaveable.

**#15** 30 tests across both suites, including corrupt-JSON recovery (a bad value yields an empty list rather than making Settings unopenable).

Gate: fast gate TEST SUCCEEDED, BUILD SUCCEEDED, swiftlint 0 violations in 357 files, swiftformat 0.61.1 clean, tooltip check passes.

not verified: (visual) — the Settings section's layout, the insertion menu and the preview pane were not seen rendered.
<!-- SECTION:FINAL_SUMMARY:END -->
