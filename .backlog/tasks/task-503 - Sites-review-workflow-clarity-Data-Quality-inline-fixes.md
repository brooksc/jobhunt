---
id: TASK-503
title: Sites review workflow clarity + Data Quality inline fixes
status: To Do
assignee: []
created_date: '2026-06-18 23:06'
updated_date: '2026-07-21 22:59'
labels:
  - ux
  - sites
  - data-quality
dependencies: []
priority: medium
ordinal: 5000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Two punted review areas to think through later:

#16 — Sites review cadence is unclear: "Overdue 6d" with no inline "Mark Reviewed" (must open the detail), no explanation that reviewing resets the clock, and "Exclude" has no re-enable. Improve: inline Mark-Reviewed action in the row, a one-line explainer when sites are overdue, a clearer "Check every N days" affordance, and a Re-enable button for excluded sites.

#17 — Data Quality lists issues you can't fix inline (e.g. "Missing company" with no field to type it; only re-extract — which re-fails on a dead source URL — or mark-reviewed which just hides it). Add quick-fix affordances: inline edit for missing fields, and surface the extraction error + a manual-entry path when re-extraction isn't viable.

References: app/Views/Sites/SitesView.swift, app/Views/Sites/SiteDetailView.swift, core/Services/SiteService.swift, app/Views/Quality/DataQualityView.swift.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Sites: inline Mark-Reviewed + clearer cadence affordance + re-enable for excluded sites
- [ ] #2 Data Quality: at least the common missing-field issues can be fixed inline (or via a clear manual-entry path)
<!-- AC:END -->
