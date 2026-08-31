---
id: TASK-696
title: >-
  Documentation audit: retire the Electron-era residue and decide update vs
  delete for every doc
status: To Do
assignee: []
created_date: '2026-08-31 18:27'
labels: []
dependencies: []
priority: medium
type: docs
ordinal: 70000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Raised 2026-08-31. The Swift rewrite's cutover task ([[TASK-064]]) is marked **Done with all four acceptance criteria unchecked**, and its final summary claims "README and docs updated". The code half genuinely happened — `electron/`, `static/`, `native/`, `package.json` are all gone. The documentation half did not.

## What's left

**35 `Electron` references in Swift/JS source.** Almost all are "Electron parity" comments, e.g.

```
core/LLM/LocationCriteria.swift:3   /// … — Electron parity with
core/LLM/Providers/GoogleProvider.swift:14   /// … (TASK-463, Electron parity ~4 RL retries).
```

**These are not simply deletable, and that is the whole point of this task.** Each one encodes *why* a rule exists — it matched the app that shipped before. Delete it and the rationale goes with it; keep it and the reader is pointed at a codebase that no longer exists and cannot be checked. The correct move is almost always to **rewrite the comment to state the actual reason directly** ("retry budget of 4, which is what the previous implementation used and what Google's rate limits tolerate"), preserving the knowledge and dropping the dangling reference. Deleting outright is right only where the comment says nothing beyond "parity".

**`swift-plan.md` (789 lines)** opens with "currently Electron + Node" — actively false. It is a completed migration plan. Decide: archive it under `docs/history/`, or delete it and let git hold the record.

**22 markdown files** at root and in `docs/` have never been audited as a set. Each needs a verdict: current, needs update, or delete.

## Constraints

- `CLAUDE.md`, `AGENTS.md`, `README.md`, `CONTRIBUTING.md` are load-bearing — audit and correct them, never delete.
- Per the repo's own convention, do not delete anything merely because it looks unused. Propose, then have a human confirm the deletions.
- Backlog files under `.backlog/` are a historical record; Electron references there are correct and must be left alone.

Also reopen or supersede [[TASK-064]] rather than leaving a Done task whose criteria are unchecked and whose summary overstates what happened.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Every 'Electron parity' comment in source is either rewritten to state the reason directly or removed, with no dangling reference to a codebase that no longer exists
- [ ] #2 swift-plan.md is archived or deleted by explicit decision, not left claiming the app is 'currently Electron + Node'
- [ ] #3 All 22 markdown docs carry a verdict: current, updated, or deleted
- [ ] #4 README/CONTRIBUTING/CLAUDE.md/AGENTS.md are verified accurate against the Swift-only repo
- [ ] #5 Backlog files under .backlog/ are untouched
- [ ] #6 TASK-064 is reopened or superseded rather than left Done with unchecked criteria
<!-- AC:END -->
