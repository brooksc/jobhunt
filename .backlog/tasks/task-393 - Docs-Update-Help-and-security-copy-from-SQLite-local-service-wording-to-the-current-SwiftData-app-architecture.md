---
id: TASK-393
title: >-
  Docs: Update Help and security copy from SQLite/local-service wording to the
  current SwiftData app architecture
status: To Do
assignee: []
created_date: '2026-06-12 23:02'
labels:
  - audit
  - docs
  - help
  - architecture
dependencies: []
references:
  - app/Views/Help/HelpView.swift
  - README.md
  - SECURITY.md
  - docs/chrome-web-store-review.md
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
The in-app Help and some review/security docs still describe captures as being stored in SQLite by a local service. The current app is a SwiftData-native macOS app, even though backups copy the underlying SQLite store. Update user-facing architecture language so it matches README/privacy terminology without overexposing implementation details.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 In-app Help describes storage consistently with current SwiftData app architecture.
- [ ] #2 Security/review docs distinguish user-facing SwiftData storage from underlying SQLite backup/store implementation where relevant.
- [ ] #3 Chrome review notes no longer imply a legacy local-service storage architecture.
- [ ] #4 README, Help, Privacy, and Security docs use compatible storage terminology.
<!-- AC:END -->
