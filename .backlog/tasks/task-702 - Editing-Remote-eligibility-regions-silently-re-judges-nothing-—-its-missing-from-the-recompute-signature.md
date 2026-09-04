---
id: TASK-702
title: >-
  Editing Remote eligibility regions silently re-judges nothing — it's missing
  from the recompute signature
status: Done
assignee: []
created_date: '2026-08-31 19:28'
updated_date: '2026-09-04 19:52'
labels: []
dependencies: []
priority: high
type: bug
ordinal: 76000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
From the 2026-08-31 correctness audit (`scratchpad/audit-bugs.md`, #1). **Verified.** One-line fix.

`locationCriteriaSignature` (`app/Views/Settings/SettingsTab.swift:175-186`) is the `.task(id:)` key that triggers re-judging every stored job's `meetsCriteria` when location settings change. Its own doc comment says it lists **"Every input `LocationCriteria` reads"**. It lists six. It omits `remoteEligibilityRegions`.

`LocationCriteria` does read it — `core/LLM/LocationCriteria.swift:31` and `:48` — and it is the **dominant term for remote roles**, which is most of the library: 1,032 of 1,591 jobs are `remote`.

The field is editable in the same settings section, at `SettingsTab.swift:253`. So a user edits Remote eligibility regions, the signature is unchanged, `.task(id:)` never restarts, no job is re-judged, and every stored `meetsCriteria` keeps its verdict from the old regions. The Jobs filter then disagrees with the settings that produced it — which is, verbatim, the failure the comment immediately below the signature says this feature exists to prevent:

> Changing the location settings used to affect only jobs extracted *afterwards* — the existing library kept its old verdicts until someone ran `JobhuntMigrator --recompute-criteria`, which meant the Jobs filter silently disagreed with the settings.

Nothing on screen indicates it. The user sees a saved setting and a stale library.

**Fix:** add `settings.remoteEligibilityRegions` to the array.

**Then stop it recurring.** This is the third instance today of a hand-maintained "list of every input X reads" drifting from what X actually reads (`check-docs.sh` and `KeyboardShortcutCatalog` are the others). Either derive the signature from the same source `LocationCriteria` takes its arguments from, or add a test that constructs a `LocationCriteria` call and asserts each of its settings-derived parameters appears in the signature. A comment claiming completeness is not a mechanism.

Existing rows are repairable with `JobhuntMigrator --recompute-criteria`, which is presumably why nobody noticed.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 remoteEligibilityRegions is included in locationCriteriaSignature
- [ ] #2 Editing Remote eligibility regions re-judges the library, verified by a test
- [ ] #3 A test or derivation prevents a future LocationCriteria input from being omitted from the signature
- [ ] #4 Existing stored verdicts are corrected via --recompute-criteria
<!-- AC:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Fixed in 0b58d9cb (merged via 4edfbe6b). The `.task(id:)` key was a hand-written string listing "every input LocationCriteria reads"; it listed six and omitted `remoteEligibilityRegions` — the dominant term for remote roles, and editable in that very view, so editing it left every stored verdict stale. The inputs are now derived from a struct rather than hand-listed, so the next added field can't be silently forgotten (`app/Views/Settings/SettingsTab.swift:176-223`).

Status corrected 2026-09-04 — landed 2026-08-31, never flipped.
<!-- SECTION:FINAL_SUMMARY:END -->
