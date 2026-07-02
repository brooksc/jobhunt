---
id: TASK-590
title: 'Spotlight: index jobs via CSSearchableIndex for system-wide search'
status: To Do
assignee: []
created_date: '2026-07-02 21:52'
labels: []
dependencies: []
references:
  - app/Platform/PlatformIntegration.swift
  - app/Views/Settings/DataSettingsView.swift
priority: low
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
- [ ] #1 Typing a company name or job title in macOS Spotlight returns matching jobs
- [ ] #2 Clicking a Spotlight result opens the app at that job (deep link)
- [ ] #3 Deleting a job removes it from the Spotlight index
- [ ] #4 Settings → Data has a 'Clear Spotlight Index' option
<!-- AC:END -->
