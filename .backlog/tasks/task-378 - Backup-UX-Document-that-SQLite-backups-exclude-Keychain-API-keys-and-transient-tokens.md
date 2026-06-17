---
id: TASK-378
title: >-
  Backup UX: Document that SQLite backups exclude Keychain API keys and
  transient tokens
status: Done
assignee: []
created_date: '2026-06-12 22:45'
updated_date: '2026-06-17 05:17'
labels:
  - audit
  - backup
  - privacy
  - documentation
dependencies: []
references:
  - core/Services/BackupService.swift
  - core/Settings/SettingsStore.swift
  - app/Views/Settings/SettingsTab.swift
priority: low
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
BackupService documentation and UI imply full-fidelity data backup, but API keys are stored in Keychain and MCP tokens are transient files, so they are not included in the SQLite backup.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Backup and restore UI/help text clearly states that API keys must be re-entered after restore or migration when Keychain items are unavailable.
- [x] #2 Developer documentation distinguishes SQLite-backed settings from Keychain secrets and transient MCP tokens.
- [x] #3 A backup/restore smoke checklist verifies provider settings and API-key state after restore.
<!-- AC:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Backups copy the SQLite store only; AI provider API keys live in the macOS Keychain (`KeychainStore`) and the MCP bridge token is a transient file (`~/.jobhunt-mcp-token`, `MCPTokenManager`), so neither is in a snapshot. Documented this at every touchpoint:

- **AC#1 (UI/help text):** `app/Views/Settings/SettingsTab.swift` — new caption under the Back Up / Restore buttons; added a line to the restore-confirmation dialog message and to the post-restore "Restore Complete" alert, all stating API keys must be re-entered in AI Provider settings after restore when the Keychain items aren't present (e.g. a new Mac).
- **AC#2 (dev docs):** `core/Services/BackupService.swift` header — a "What is and isn't in the backup" section distinguishing store-backed settings rows (provider/model selection) from the Keychain-held API keys and the transient MCP token.
- **AC#3 (smoke checklist):** `CLAUDE.md` backup section — a secrets-not-in-backup note plus a 5-step backup/restore smoke checklist (job count, AI Provider settings + API-key field state, an end-to-end extraction/fit-score, an extension capture, resumes/sites spot-check).

Build verified (Jobhunt-DMG, BUILD SUCCEEDED). Note the SettingsTab caption deliberately avoids markdown emphasis: the strings are concatenated at runtime, and `Text(String)` (vs `Text(LocalizedStringKey)`) doesn't render markdown — `**not**` would have shown literal asterisks.
<!-- SECTION:FINAL_SUMMARY:END -->
