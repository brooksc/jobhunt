---
id: TASK-547
title: 'Onboarding: surface resume persistence failures after file import'
status: To Do
assignee: []
created_date: '2026-06-19 22:18'
labels:
  - audit
  - ux
  - onboarding
  - resume
  - import
dependencies: []
references:
  - app/Views/Onboarding/OnboardingView.swift
  - app/Views/Settings/ResumesTab.swift
  - core/Services/ResumeService.swift
  - tests/AppUITests/BehaviorUITests.swift
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Finding: onboarding resume import reads the selected PDF/text file, updates the UI to show the resume name/text, clears `importError`, then saves asynchronously via `saveResume`. If `ResumeService.addResume` throws, `saveResume` catches the error and silently ignores it. The user can proceed believing the resume was imported, but no resume may exist after onboarding.

Why this matters: the resume is required for fit scoring. A failed persistence write at first-run setup should be visible and actionable. Settings' resume edit flow already surfaces save failures; onboarding should not treat a save failure as non-fatal once it has shown the user a successful import state.

Suggested implementation: fold file-read and persistence into one explicit async flow, or keep the preview state separate from persisted state. Show a save error if `addResume` fails, keep the user on the resume step, and avoid showing a check/success state that implies persistence until the service call succeeds. Consider reusing the same save-error pattern as `ResumeEditSheet`.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 If `ResumeService.addResume` fails during onboarding import, the user sees a clear error message.
- [ ] #2 The onboarding UI does not show the resume as successfully imported/persisted unless the save succeeds.
- [ ] #3 The user can retry import/save or skip intentionally after a save failure.
- [ ] #4 Successful PDF/text import still uses security-scoped access and persists through `ResumeService`.
- [ ] #5 A test seam or UI test covers a simulated resume save failure during onboarding.
<!-- AC:END -->
