---
id: TASK-586
title: >-
  SettingsStore.set: propagate keychain write failure to caller instead of
  silently setting flag
status: Done
assignee: []
created_date: '2026-07-02 21:51'
updated_date: '2026-08-09 19:08'
labels: []
dependencies:
  - TASK-569
references:
  - 'core/Settings/SettingsStore.swift:79'
priority: low
ordinal: 35000
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
- [x] #1 SettingsStore.set throws on keychain failure rather than silently returning
- [x] #2 Existing call sites compile (use try? where the error was already silently swallowed)
- [x] #3 keychainWriteError is still set for UI observation, but the throw also fires so programmatic callers know
<!-- AC:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
`SettingsStore.set(_:forKey:)` and `setAPIKey(_:forProvider:)` both throw now. Both previously caught the keychain error, set `keychainWriteError`, and returned normally — so a programmatic caller (restore, key rotation) was told a key had been stored when it hadn't. `keychainWriteError` is still set before the throw, so the UI path is unchanged; the throw is additional.

`setAPIKey` was swallowing identically and isn't mentioned in the original report, but it is the path the API-key field actually uses — fixing only `set` would have left the real one silent.

**Judgement call:** SwiftUI property setters can't throw, and the typed shortcuts (`llmProvider`, `llmModel`, sort key, sidebar selection…) would have needed `try?`, putting silent failure back exactly where it was removed. They now route through a private non-throwing `setLocal`, which asserts the key is not keychain-backed. All six `keychainKeys` are API keys, so no shortcut property can reach the throwing path; the assert holds that line if a key ever changes category.

Call sites that write plain settings use `try?` with a comment saying the error cannot occur — explicit, not accidental. The one interactive keychain caller (`AIProviderFormModel.onAPIKeyChanged`) also uses `try?`, because it cannot propagate and `keychainWriteError` is already rendered by `SettingsView`.

**Tests** (`SettingsStoreKeychainFailureTests`, 4) using a `RefusingKeychain` double: `set` throws, `setAPIKey` throws, `keychainWriteError` is still populated for the UI, and ordinary settings still write cleanly through the same entry point.
<!-- SECTION:FINAL_SUMMARY:END -->
