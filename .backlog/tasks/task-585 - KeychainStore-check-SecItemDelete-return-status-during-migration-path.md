---
id: TASK-585
title: 'KeychainStore: check SecItemDelete return status during migration path'
status: Done
assignee: []
created_date: '2026-07-02 21:51'
updated_date: '2026-07-22 00:46'
labels: []
dependencies:
  - TASK-569
references:
  - 'core/Settings/KeychainStore.swift:26'
priority: low
ordinal: 34000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
**Problem:** `KeychainStore.swift:set(_:forKey:)` (lines 26–41) does a delete-then-add when migrating an existing keychain item to pick up the correct security policy. The `SecItemDelete()` call's return status is not checked. If deletion fails (e.g. ACL restriction, wrong kSecAttrService), the subsequent `SecItemAdd()` also fails with a cryptic `errSecDuplicateItem` (or similar), and the error message doesn't indicate that the delete step was the root cause.

**How to fix:**
```swift
let deleteStatus = SecItemDelete(searchQuery as CFDictionary)
guard deleteStatus == errSecSuccess || deleteStatus == errSecItemNotFound else {
    throw KeychainError.deleteFailed(deleteStatus)
}
```
Add `case deleteFailed(OSStatus)` to `KeychainError` if it doesn't exist, or reuse the existing error type.

**Note:** This is the companion bug to TASK-569 (distinguishing read failures from missing keys). Consider batching them.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 SecItemDelete status is checked; a non-success, non-errSecItemNotFound status throws a typed error
- [ ] #2 The thrown error propagates up through SettingsStore so the UI can surface it (ties into TASK-569 work)
<!-- AC:END -->
