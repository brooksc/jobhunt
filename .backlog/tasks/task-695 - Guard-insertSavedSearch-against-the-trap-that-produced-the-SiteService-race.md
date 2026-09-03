---
id: TASK-695
title: Guard insertSavedSearch against the trap that produced the SiteService race
status: To Do
assignee: []
created_date: '2026-08-31 18:26'
labels: []
dependencies: []
priority: medium
type: chore
ordinal: 92000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
From the TASK-692 recon (2026-08-31). `JobService.insertSavedSearch(_ search: SavedSearch)` (`core/Services/JobService.swift:762-764`) takes a `@Model` across an isolation boundary. It is safe today **only** because no current caller builds its argument from a fetched row — nothing in the signature, and no comment, enforces that.

A future caller writing the obvious next line —

```swift
let s = existing.first!
s.name = newName
try await insertSavedSearch(s)
```

— makes it a live data race with **no new compiler warning**, because the parameter is still a plain `SavedSearch`. The caller side (`app/Views/Jobs/SaveSearchSheet.swift:121`) is the same shape.

This is not hypothetical: it is exactly how the `SiteService` race (TASK-692 R3) arose — nothing was wrong until someone read an id back off a transferred model.

Two parts, which should land together so the keyword and its rationale arrive as one change:

1. Mark the parameter `sending`, so the mistake becomes a compiler error rather than heap corruption. (Tracked as commit C3 in the wave plan.)
2. **Add a comment on the declaration** in the register the codebase already uses for this — see `core/Services/BackgroundStore.swift:1193-1198` ("must never read or mutate a live @Model fetched from this @ModelActor") and the `AvailabilityChecker.JobInput` doc comment. It should say: this takes ownership of a freshly-constructed row; never pass a `SavedSearch` obtained from a fetch, and never touch it after the call; the `sending` annotation is what makes that a compiler error.

A `sending` parameter with no explanation is a puzzle. With the comment it is a rule.

Plan: `scratchpad/task-692-plan.md` (Wave C, C3). Parent issue: [[TASK-692]].
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 insertSavedSearch's parameter is marked `sending`
- [ ] #2 Passing a fetched SavedSearch to it is a compile error, demonstrated by a comment or test
- [ ] #3 The declaration carries a comment explaining the ownership rule, matching the register of BackgroundStore.swift:1193-1198
- [ ] #4 SaveSearchSheet.swift:121 still compiles and behaves identically
<!-- AC:END -->
