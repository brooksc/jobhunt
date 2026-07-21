---
id: TASK-569
title: 'Settings: distinguish Keychain read failures from missing API keys'
status: To Do
assignee: []
created_date: '2026-06-20 04:10'
updated_date: '2026-07-21 22:59'
labels:
  - audit
  - settings
  - keychain
  - diagnostics
dependencies: []
modified_files:
  - core/Settings/KeychainStore.swift
  - core/Settings/SettingsStore.swift
  - core/LLM/AIReadiness.swift
  - app/Views/Settings/SettingsView.swift
  - app/Views/Settings/DebugTab.swift
  - tests/CoreTests/SettingsStoreTests.swift
priority: low
ordinal: 28000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Finding: `KeychainStore.get(_:)` returns nil for every non-success `SecItemCopyMatching` status, so `SettingsStore.apiKey(forProvider:)` cannot distinguish a genuinely missing API key from Keychain access failure, locked keychain, ACL denial, or unexpected data. `AIReadiness` then interprets that as an unconfigured provider.

Why it matters: This collapses operational failures into user configuration state. A user with a saved key can be told to set up AI again, and support diagnostics lose the OSStatus that would explain whether the key is missing, inaccessible, or corrupted. This is separate from keychain write visibility: write errors are surfaced, but read errors are currently invisible.

Suggested implementation: Add a throwing or status-returning read path, for example `KeychainStore.getResult(_:) -> Result<String?, KeychainError>` or `throws -> String?`, treating only `errSecItemNotFound` as normal absence. Have `SettingsStore` retain a redacted `keychainReadError` similar to `keychainWriteError`, and have readiness/UI diagnostics distinguish `missingAPIKey` from `apiKeyUnavailable`. Keep the existing convenience getter if needed for low-risk callers, but route AI readiness and diagnostics through the error-aware path.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Keychain `errSecItemNotFound` remains a normal missing-key result.
- [ ] #2 Other Keychain read statuses are preserved as redacted errors instead of being collapsed to nil.
- [ ] #3 AI readiness or settings UI can distinguish missing API key from API key unavailable due to Keychain read failure.
- [ ] #4 Diagnostics include the keychain read error type/status without exposing secret values.
- [ ] #5 Unit tests cover not-found vs read-failure behavior with an injectable/fake keychain path.
<!-- AC:END -->
