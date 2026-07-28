---
id: TASK-652
title: >-
  JobhuntMigrator binary goes stale silently — a data fixup can run old logic
  against the live store
status: To Do
assignee: []
created_date: '2026-07-28 02:54'
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

**This is a data-integrity hazard, not a build annoyance.** The migrator's entire purpose is deliberate, out-of-band fixups against the production store with the app quit (see CLAUDE.md "One-time data operations"). A stale binary means a fixup can report success while doing nothing — or worse, apply superseded logic to real data. The operator has no signal: the version isn't printed, and "0 corrected" is indistinguishable from "already correct".

Rebuilding proved unreliable in three ways:
- `xcodebuild -target JobhuntMigrator -configuration Debug-DMG` reports BUILD SUCCEEDED but emits only `JobhuntMigrator.swiftmodule` — no executable at the products path.
- After deleting the binary, `xcodebuild -scheme Jobhunt-DMG build` also reports success without regenerating it.
- The stale binary's mtime therefore stayed put across several "successful" builds, which is what made it hard to spot.

The backfill was ultimately done with a targeted SQL UPDATE against the quit store (safe here: `ZFITSTATUS` is plain text and only scalar mirror columns were touched, with a fresh backup taken first) — but that is not a pattern to rely on.

Wanted:
- A documented, reliable way to build the migrator (script or Tuist/scheme fix) so the binary always matches the source.
- The migrator should print its build identity on startup (marketing version + git SHA or build timestamp) so the operator can see what they're about to run against production data.
- Consider having `scripts/rebuild-and-run.sh` or a dedicated `scripts/build-migrator.sh` produce it, so the documented workflow can't silently use a months-old binary.</description>
<parameter name="acceptanceCriteria">["A documented command reliably produces a JobhuntMigrator executable matching current source", "The migrator prints its version/build identity before performing any mutation", "Running a mode against an out-of-date binary is detectable by the operator", "tools/migrator/README.md documents how to build it, not just how to run it"]
<!-- SECTION:DESCRIPTION:END -->
