---
id: TASK-276
title: 'Resume: Route onboarding resume creation through ResumeService'
status: To Do
assignee: []
created_date: '2026-06-12 03:34'
labels:
  - audit
  - resume
  - onboarding
  - data-consistency
dependencies: []
references:
  - app/Views/Onboarding/OnboardingView.swift
  - core/Services/ResumeService.swift
  - tests/CoreTests/ResumeServiceTests.swift
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Onboarding directly inserts Resume(active: true, sortOrder: 0), bypassing ResumeService invariants. Use the service or shared helper so onboarding cannot create multiple active resumes or duplicate sort order values.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Onboarding resume creation uses ResumeService or equivalent shared invariant-preserving code.
- [ ] #2 Adding a resume from onboarding when resumes already exist preserves exactly one active resume unless explicitly changed.
- [ ] #3 Tests cover onboarding-style import with existing resumes.
<!-- AC:END -->
