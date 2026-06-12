---
id: TASK-221
title: 'Docs: Fix stale SQLite storage path in security policy'
status: Done
assignee: []
created_date: '2026-06-12 01:06'
updated_date: '2026-06-12 02:00'
labels:
  - docs
  - security
  - privacy
dependencies: []
references:
  - SECURITY.md
  - PRIVACY.md
priority: low
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
SECURITY.md still says the SQLite database is stored under ~/.config/jobhunt/, while current privacy docs and app behavior use Application Support/container paths. Align the security policy with the current storage locations.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 SECURITY.md documents the current direct-download and Mac App Store database paths.
- [ ] #2 PRIVACY.md and SECURITY.md use consistent storage terminology.
- [ ] #3 Any release/marketing copy that repeats the old path is updated or verified absent.
<!-- AC:END -->
