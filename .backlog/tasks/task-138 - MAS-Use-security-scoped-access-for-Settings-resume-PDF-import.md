---
id: TASK-138
title: 'MAS: Use security-scoped access for Settings resume PDF import'
status: To Do
assignee: []
created_date: '2026-06-11 03:40'
labels:
  - mas
  - sandbox
  - privacy
  - resume-import
dependencies: []
references:
  - app/Views/Settings/ResumesTab.swift
  - app/Views/Onboarding/OnboardingView.swift
  - build/Jobhunt-MAS.entitlements
  - docs/MAS-VALIDATION.md
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Onboarding resume import correctly starts and stops security-scoped access before reading selected files. Settings PDF import uses NSOpenPanel then reads PDFDocument directly, which can fail under MAS sandboxing for user-selected files.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Settings resume PDF import calls startAccessingSecurityScopedResource before reading the selected URL and balances it with stopAccessingSecurityScopedResource.
- [ ] #2 Settings and onboarding import paths share a small helper or otherwise use consistent sandbox-safe file access behavior.
- [ ] #3 MAS validation checklist includes Settings resume PDF import, not only onboarding import.
- [ ] #4 A sandboxed MAS build or sandbox simulation verifies PDF import succeeds from outside the app container.
<!-- AC:END -->
