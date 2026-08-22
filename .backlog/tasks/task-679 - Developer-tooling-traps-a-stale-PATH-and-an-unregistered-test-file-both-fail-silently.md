---
id: TASK-679
title: >-
  Developer-tooling traps: a stale PATH and an unregistered test file both fail
  silently
status: Done
assignee: []
created_date: '2026-08-21 02:19'
updated_date: '2026-08-22 18:48'
labels:
  - tooling
  - tech-debt
dependencies: []
priority: medium
ordinal: 50000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Two ways the local toolchain lies about whether your work is checked. Both were hit in one session.

1. scripts/rebuild-and-run.sh calls bare 'swiftformat'. On this Mac that resolves to Homebrew's newer build rather than the .mise.toml pin (0.61.1), which reports ~108 files needing formatting and, under 'set -e', aborts the script BEFORE it builds. docs/backlog-triage-2026-08.md records this same mismatch keeping main red for a week. The script should resolve the pinned binaries itself instead of trusting PATH.

2. extension/package.json lists its test files explicitly, so a newly added test file is simply never run — locally or in CI — until someone remembers to add it. A new preflight-salary suite sat unrun until noticed by accident; adding it took the count from 124 to 135. Prefer a glob, or a check that every tests/*.js appears in the script.

Neither is a product bug. Both are the kind of thing that makes a green run meaningless.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 rebuild-and-run.sh uses the mise-pinned swiftformat/swiftlint regardless of PATH
- [ ] #2 A new extension test file runs without being registered by hand, or CI fails when one is unregistered
<!-- AC:END -->
