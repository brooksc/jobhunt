---
id: TASK-586
title: >-
  SettingsStore.set: propagate keychain write failure to caller instead of
  silently setting flag
status: To Do
assignee: []
created_date: '2026-07-02 21:51'
labels: []
dependencies:
  - TASK-569
references:
  - 'core/Settings/SettingsStore.swift:79'
priority: low
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
**Problem:** `SettingsStore.set(_:forKey:)` (lines 79–91) catches a keychain write error, sets `keychainWriteError`, and returns — with no indication of failure to the caller. Programmatic callers (e.g. a future automated key rotation or restore path) believe the write succeeded. The UI shows an error via `keychainWriteError`, but that only helps interactive flows.

**How to fix:**
Change the method signature to `throws` (or return a `Bool`/`Result`) and re-throw keychain errors so callers can handle them:
```swift
public func set(_ value: String, forKey key: String) throws {
    if SettingsKey.keychainKeys.contains(key) {
        try keychain.set(value, forKey: key)   // let it throw
        keychainWriteError = nil
        return
    }
    // ... non-keychain path unchanged
}
```
All current call sites that don't care can use `try?`; the ones that do (import/restore flows) can propagate.

**Note:** Batch with TASK-569 since both touch the keychain error-surfacing story.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 SettingsStore.set throws on keychain failure rather than silently returning
- [ ] #2 Existing call sites compile (use try? where the error was already silently swallowed)
- [ ] #3 keychainWriteError is still set for UI observation, but the throw also fires so programmatic callers know
<!-- AC:END -->
