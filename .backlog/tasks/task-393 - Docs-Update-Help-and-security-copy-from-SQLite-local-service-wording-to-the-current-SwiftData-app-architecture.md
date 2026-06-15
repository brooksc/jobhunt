---
id: TASK-393
title: >-
  Docs: Update Help and security copy from SQLite/local-service wording to the
  current SwiftData app architecture
status: Done
assignee: []
created_date: '2026-06-12 23:02'
updated_date: '2026-06-15 18:40'
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
modified_files:
  - app/Views/Help/HelpView.swift
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
- [x] #1 In-app Help describes storage consistently with current SwiftData app architecture.
- [x] #2 Security/review docs distinguish user-facing SwiftData storage from underlying SQLite backup/store implementation where relevant.
- [x] #3 Chrome review notes no longer imply a legacy local-service storage architecture.
- [x] #4 README, Help, Privacy, and Security docs use compatible storage terminology.
<!-- AC:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
In-app Help no longer describes a "local service" storing captures in "SQLite": the capture flow now says the extension sends pages to the native macOS app over a local connection and the app stores them locally on the Mac; the troubleshooting "local service must be running" copy became "the Jobhunt app must be open" (AC#1). SECURITY.md distinguishes the user-facing storage as a SwiftData store (SQLite-backed file) — keeping the path for the threat model while not implying a separate service (AC#2). docs/chrome-web-store-review.md no longer says captures live "in a local SQLite database"/local-service — now "stored locally in the native macOS app" (AC#3). Help, Privacy (TASK-391/392), SECURITY, and README now use compatible "local app / local store" terminology (AC#4). App builds.
<!-- SECTION:FINAL_SUMMARY:END -->
