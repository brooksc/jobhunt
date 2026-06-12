---
id: TASK-243
title: 'Resume import: Surface Settings import failures consistently'
status: Done
assignee: []
created_date: '2026-06-12 02:02'
updated_date: '2026-06-12 02:16'
labels:
  - resumes
  - import
  - ux
dependencies: []
references:
  - app/Views/Settings/ResumesTab.swift
  - app/Views/Onboarding/OnboardingView.swift
  - docs/MAS-VALIDATION.md
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Onboarding reports resume import errors, but Settings PDF import silently returns on denied security scope, unreadable PDF, or empty extraction. Align Settings import with onboarding so users get actionable failure messages.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Settings resume import shows an error when security-scoped access is denied.
- [ ] #2 Unreadable PDFs and empty extracted text produce visible messages.
- [ ] #3 Settings and onboarding share import helper logic where practical.
- [ ] #4 Tests or manual checks cover permission denied, unreadable PDF, and successful import paths.
<!-- AC:END -->
