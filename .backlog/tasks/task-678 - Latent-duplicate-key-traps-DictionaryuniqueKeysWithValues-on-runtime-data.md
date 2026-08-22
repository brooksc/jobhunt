---
id: TASK-678
title: 'Latent duplicate-key traps: Dictionary(uniqueKeysWithValues:) on runtime data'
status: Done
assignee: []
created_date: '2026-08-21 02:19'
updated_date: '2026-08-22 20:29'
labels:
  - bug
  - crash
  - tech-debt
dependencies: []
priority: medium
ordinal: 49000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
A repeated URL query parameter crashed the whole app this session (Netflix's ?Teams=a&Teams=b through RemoteTypeInferer.urlIndicatesRemote — fixed). The same construct is used on runtime data in one more place:

  BackgroundStore.setJobStatus:132
    let jobsByID = Dictionary(uniqueKeysWithValues: allJobs.map { (\/bin/zsh.id, \/bin/zsh) })

Two jobs sharing an id would trap there, taking the process down on an ordinary status change. The live store has zero duplicates today, so this is latent rather than live — and the codebase has previously needed a migrator mode to repair duplicate jobNumbers, so duplicate keys in this data are not unthinkable.

Deliberately NOT fixed blind: making it lenient (uniquingKeysWith:) would hide real store corruption, which is arguably worse than a crash. The decision is whether to fail loudly with a diagnosable error instead of a trap, and whether a duplicate-id check belongs in the migrator's repair modes alongside --repair-duplicate-job-numbers.

The remaining two uses (stateNameToAbbrev, RemoteGeography's inverted table) are static tables with provably unique keys and are fine.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 A duplicate job id cannot take the process down on a status change
- [ ] #2 Whatever replaces the trap surfaces the corruption rather than silently tolerating it
<!-- AC:END -->
