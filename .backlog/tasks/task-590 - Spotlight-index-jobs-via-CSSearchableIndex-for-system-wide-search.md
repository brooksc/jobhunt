---
id: TASK-590
title: 'Spotlight: index jobs via CSSearchableIndex for system-wide search'
status: Done
assignee: []
created_date: '2026-07-02 21:52'
updated_date: '2026-08-10 01:13'
labels: []
dependencies: []
references:
  - app/Platform/PlatformIntegration.swift
  - app/Views/Settings/DataSettingsView.swift
modified_files:
  - core/Services/SpotlightEntry.swift
  - core/Services/BackgroundStore.swift
  - core/Services/JobService.swift
  - app/Platform/SpotlightIndexer.swift
  - app/Shell/AppServices.swift
  - app/Views/Settings/DataSettingsTab.swift
  - app/Views/Jobs/JobsView.swift
  - app/Views/Detail/JobDetailView.swift
  - tests/CoreTests/SpotlightEntryTests.swift
priority: low
ordinal: 39000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
**Opportunity:** Jobs are only searchable inside the app. Adding `CSSearchableIndex` integration lets users find jobs from Spotlight, Mission Control search, or Safari address bar — a "good Mac citizen" feature with no ongoing maintenance burden.

**How to implement:**
1. Add `import CoreSpotlight` to a new `SpotlightIndexer.swift` in `app/Platform/`.
2. On job create/update/delete, build a `CSSearchableItem` with:
   - `uniqueIdentifier`: `"jobhunt-job-\(job.jobNumber)"`
   - `attributeSet.title`: `"\(job.title) at \(job.company)"`
   - `attributeSet.contentDescription`: location, salary range, status
   - `attributeSet.keywords`: extracted skills array
   - `attributeSet.url`: `URL(string: "jobhunt://jobs/\(job.jobNumber)")`
3. Call `CSSearchableIndex.default().indexSearchableItems([item])` — batch on launch for existing jobs (one-time pass), then incrementally on change.
4. On job delete: `CSSearchableIndex.default().deleteSearchableItems(withIdentifiers: [id])`.
5. Add a "Clear Spotlight Index" button in Settings → Data alongside the existing backup controls.

**Scope:** ~100 lines. No schema changes. DMG build only (MAS sandbox complicates Spotlight — defer that variant).

**Parked — no urgency.** Good candidate for a quiet week.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 not verified: (visual) — Spotlight results were not exercised on a live desktop. The indexed title, keywords and description are unit-tested and the CoreSpotlight call is compile-checked.
- [ ] #2 not verified: (visual) — clicking a Spotlight result was not exercised. The item carries the same jobhunt://jobs/N link the notification path already uses and PlatformIntegration.handleDeepLink already resolves.
- [x] #3 Deleting a job removes it from the Spotlight index
- [x] #4 Settings → Data has a 'Clear Spotlight Index' option
<!-- AC:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
`SpotlightEntry` (Core) decides what gets indexed and is unit-tested; `SpotlightIndexer` (app) is a thin CoreSpotlight adapter, since the framework can't be exercised in a unit test.

#1/#2 are implemented but rewritten `not verified: (visual)` — confirming a Spotlight result appears and opens needs a live desktop, which is out of bounds for this run. The link is `jobhunt://jobs/N`, the same one the follow-up notifications use and `PlatformIntegration.handleDeepLink` already resolves, so #2 rides on an existing, working path rather than a new one.

#3 The delete paths read the job number **before** deleting — afterwards there's nothing to read — and remove the item. A stale hit that opens the app onto a missing job is the failure worth avoiding.

#4 "Clear Spotlight Index" in Settings → Data, scoped to this app's domain identifier rather than a global index wipe.

**Judgement calls.** A job with no number isn't indexed (a hit that opens the app and lands nowhere is worse than no hit) and neither is one with no title *and* no company (a blank row). The company is added as a keyword as well as appearing in the title, so searching "Acme" finds every Acme job whatever its title reads like. Indexing is a one-shot pass 5s after launch rather than a change observer: a few hundred rows are cheap to re-index, and an entry going stale until the next launch is a far smaller problem than an observer firing on every extraction write.

9 tests. Two SwiftLint limits tripped by the additions — fixed by extracting `DataSettingsTab` to its own file and the two runtime loops into named methods, rather than by raising the limits.

Gate: fast gate TEST SUCCEEDED, BUILD SUCCEEDED, swiftlint 0 violations in 353 files, swiftformat 0.61.1 clean, tooltip check passes.
<!-- SECTION:FINAL_SUMMARY:END -->
