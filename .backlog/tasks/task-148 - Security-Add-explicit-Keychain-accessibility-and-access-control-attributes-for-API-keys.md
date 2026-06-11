---
id: TASK-148
title: >-
  Security: Add explicit Keychain accessibility and access-control attributes
  for API keys
status: Done
assignee: []
created_date: '2026-06-11 04:34'
updated_date: '2026-06-11 20:06'
labels:
  - security
  - keychain
  - settings
dependencies: []
references:
  - core/Settings/KeychainStore.swift
  - core/Settings/SettingsStore.swift
  - tests/CoreTests/SettingsStoreTests.swift
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Security/privacy audit finding: `KeychainStore` stores API keys as generic passwords with only service/account attributes. Protection currently depends on Security framework defaults rather than an explicit project policy.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Keychain API-key writes set an explicit `kSecAttrAccessible` policy appropriate for local app secrets, such as a ThisDeviceOnly option if sync is not intended.
- [x] #2 Existing add/update/read/delete behavior remains compatible with stored API keys or includes a documented migration path.
- [x] #3 Tests or code-review checks verify the expected accessibility attribute is present on new keychain items.
- [x] #4 The chosen accessibility policy is documented near `KeychainStore` or in privacy/security docs.
<!-- AC:END -->
