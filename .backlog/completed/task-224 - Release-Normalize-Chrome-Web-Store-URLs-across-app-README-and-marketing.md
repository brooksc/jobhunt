---
id: TASK-224
title: 'Release: Normalize Chrome Web Store URLs across app, README, and marketing'
status: Done
assignee: []
created_date: '2026-06-12 01:32'
updated_date: '2026-06-12 02:16'
labels:
  - release
  - docs
  - extension
dependencies: []
references:
  - README.md
  - app/Views/Onboarding/OnboardingView.swift
  - marketing/index.html
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
README/onboarding and marketing currently point at different Chrome Web Store extension IDs. Establish the correct listing URL in one place where practical and update all shipped surfaces.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 README, app onboarding, and marketing pages all use the same verified Chrome Web Store URL.
- [ ] #2 A lightweight check or documented release checklist catches future URL drift.
- [ ] #3 If the old listing is deprecated, docs explain the migration or removal plan.
<!-- AC:END -->
