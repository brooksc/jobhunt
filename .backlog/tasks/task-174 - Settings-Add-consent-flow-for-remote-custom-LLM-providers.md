---
id: TASK-174
title: 'Settings: Add consent flow for remote custom LLM providers'
status: Done
assignee: []
created_date: '2026-06-11 22:12'
updated_date: '2026-06-11 22:30'
labels:
  - audit
  - settings
  - llm
  - privacy
dependencies: []
references:
  - app/Views/Settings/SettingsView.swift
  - core/Settings/ConsentHelper.swift
  - core/LLM/QueueActor.swift
priority: high
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
The settings UI marks `custom` as non-cloud, so switching to the custom provider never opens the cloud consent sheet. `ConsentHelper` treats custom endpoints as local only when the base URL is loopback; remote custom URLs require consent. This means users can configure a remote custom endpoint that later fails queue processing because no consent path was available.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Custom provider consent is evaluated from the configured base URL, not only from the provider ID.
- [ ] #2 Remote custom URLs have an explicit consent grant/revoke path before job or resume data is sent.
- [ ] #3 Tests cover loopback custom URLs, remote custom URLs without consent, and remote custom URLs with consent.
<!-- AC:END -->
