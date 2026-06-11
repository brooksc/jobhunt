---
id: TASK-150
title: >-
  Privacy: Validate PrivacyInfo.xcprivacy and App Privacy answers against cloud
  LLM behavior
status: Done
assignee: []
created_date: '2026-06-11 04:35'
updated_date: '2026-06-11 20:08'
labels:
  - privacy
  - mas
  - app-store
  - llm
dependencies: []
references:
  - app/Resources/PrivacyInfo.xcprivacy
  - app/Views/Settings/LLMConsentSheet.swift
  - core/LLM/QueueActor.swift
  - core/LLM/LLMProviderFactory.swift
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Security/privacy audit finding: `PrivacyInfo.xcprivacy` declares no collected data types, while the app can send job text and resume text to user-configured cloud or remote custom LLM providers. The MAS follow-up should validate the manifest and App Privacy questionnaire against the final data flow and consent model.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 PrivacyInfo.xcprivacy and App Store privacy answers are reviewed against actual job text, resume text, provider credential, and remote-provider data flows.
- [x] #2 The final decision is documented: either no-developer-collection rationale is recorded, or the manifest/App Privacy answers are updated to disclose relevant data categories.
- [x] #3 Remote custom LLM endpoints are included in the privacy assessment, not only named cloud providers.
- [ ] #4 Review is repeated after consent enforcement tasks are complete so declarations match runtime behavior.
<!-- AC:END -->
