---
id: TASK-226
title: >-
  Release: Correct MAS validation documentation after fit-scoring consent
  enforcement is fixed
status: Done
assignee: []
created_date: '2026-06-12 01:32'
updated_date: '2026-06-12 02:16'
labels:
  - release
  - privacy
  - docs
dependencies:
  - TASK-217
references:
  - docs/MAS-VALIDATION.md
  - core/LLM/QueueActor.swift
  - app/Resources/PrivacyInfo.xcprivacy
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
MAS-VALIDATION.md says ConsentHelper enforces consent before every extraction and fit-scoring call, but fit scoring currently needs the persisted execution-time consent gate tracked separately. Update the validation evidence once the implementation is true.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 MAS validation docs no longer overstate current consent behavior.
- [ ] #2 After the fit-scoring consent fix lands, the MAS checklist references the exact tests or code paths that enforce it.
- [ ] #3 App Store privacy questionnaire guidance remains consistent with PRIVACY.md and PrivacyInfo.xcprivacy.
<!-- AC:END -->
