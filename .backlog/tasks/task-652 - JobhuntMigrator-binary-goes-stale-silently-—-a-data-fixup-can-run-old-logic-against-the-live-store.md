---
id: TASK-652
title: >-
  JobhuntMigrator binary goes stale silently — a data fixup can run old logic
  against the live store
status: To Do
assignee: []
created_date: '2026-07-28 02:54'
updated_date: '2026-07-28 02:54'
labels:
  - migrator
  - build
  - data-integrity
  - tooling
dependencies: []
references:
  - tools/migrator/README.md
  - Project.swift
  - scripts/rebuild-and-run.sh
  - core/Services/BackgroundStore.swift
priority: high
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Hit while backfilling fit mirrors after the active-résumé change (e33794c).

`JobhuntMigrator --recompute-fit-mirrors` reported "0 job mirror(s) corrected" against a store where 206 job mirrors were provably wrong — every one backed solely by an inactive résumé, verified by SQL. The logic in `BackgroundStore.computedFitMirror` was correct and its unit tests passed. The binary at `DerivedData/.../Debug-DMG/JobhuntMigrator` was simply built before the change and silently ran the old rule.

**This is a data-integrity hazard, not a build annoyance.** The migrator's whole purpose is deliberate, out-of-band fixups against the production store with the app quit (CLAUDE.md, "One-time data operations"). A stale binary means a fixup can report success while doing nothing — or worse, apply superseded logic to real data. The operator gets no signal: no version is printed, and "0 corrected" is indistinguishable from "already correct".

Rebuilding proved unreliable three ways:
- `xcodebuild -target JobhuntMigrator -configuration Debug-DMG` reports BUILD SUCCEEDED but emits only `JobhuntMigrator.swiftmodule` — no executable at the products path.
- After deleting the binary, `xcodebuild -scheme Jobhunt-DMG build` also reports success without regenerating it.
- So the stale binary's mtime stayed put across several "successful" builds, which is what made this hard to spot.

The backfill was ultimately done with a targeted SQL UPDATE against the quit store (safe in this instance: `ZFITSTATUS` is plain text and only scalar mirror columns were touched, with a fresh backup taken first) — but that is not a pattern to rely on.

Wanted:
- A documented, reliable way to build the migrator so the binary always matches source.
- The migrator should print its build identity (marketing version + git SHA or build timestamp) before any mutation, so the operator can see what they're about to run against production data.
- Consider a dedicated `scripts/build-migrator.sh` so the documented workflow can't silently use a months-old binary.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 A documented command reliably produces a JobhuntMigrator executable matching current source
- [ ] #2 The migrator prints its version/build identity before performing any mutation
- [ ] #3 Running a mode from an out-of-date binary is detectable by the operator
- [ ] #4 tools/migrator/README.md documents how to BUILD it, not just how to run it
<!-- AC:END -->
