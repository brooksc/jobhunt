---
id: TASK-170
title: 'Error handling: Make settings and API key persistence failures visible'
status: To Do
assignee: []
created_date: '2026-06-11 21:43'
labels:
  - audit
  - error-handling
  - settings
  - keychain
dependencies: []
references:
  - core/Settings/SettingsStore.swift
  - core/Settings/KeychainStore.swift
  - app/Views/Settings/SettingsView.swift
  - app/Views/Settings/LLMTab.swift
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
SettingsStore writes keychain-backed values with `try? keychain.set`, including provider API keys. If keychain persistence fails, the UI can appear to save credentials that are not actually stored. Return or publish write failures so settings screens can show a specific error and avoid misleading success states.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Keychain-backed settings writes no longer discard `KeychainError`.
- [ ] #2 Settings UI surfaces API key persistence failures to the user.
- [ ] #3 Tests or fakes cover keychain write failure behavior without requiring the real keychain.
<!-- AC:END -->
