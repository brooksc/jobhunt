---
id: TASK-051
title: 'Data Quality screen: issue-grouped lists, site health, batch review/re-extract'
status: Done
assignee: []
created_date: '2026-06-07 22:49'
updated_date: '2026-06-08 03:31'
labels:
  - swift-rewrite
  - ui
  - screen
milestone: m-1
dependencies:
  - TASK-045
  - TASK-046
documentation:
  - swift-plan.md
  - static/screens/quality.jsx
priority: medium
ordinal: 2800
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Goal: Port the Data Quality screen that surfaces jobs with missing/failed/short/stale data and lets the user batch-fix them.

## Read first
- swift-plan.md §10.2 #4 (Data Quality behavior + qualityIssuesForJob rules).
- Legacy static/screens/quality.jsx (493 lines) — summary by severity, issue-grouped lists, site-health metrics, batch actions (mark reviewed / clear / queue re-extraction / open sources), per-job issue guidance, and the qualityIssuesForJob rules (missing company/title/location/work-mode/salary; extraction failed/pending; short raw <1000B / cleaned <700B; stale >21 days).

## Implement (app/Views/Quality/)
- Port qualityIssuesForJob into a Core or view helper; group jobs by issue type with severity coloring; site-health table; deep-link from sidebar/dashboard with ?issue filter (via Router).
- Batch actions via JobService: data-quality-reviewed add/clear, bulk enqueue extract/fit, open source URLs.

## Dependencies
Depends on task-045 and task-046 (dq-review + bulk-llm). 

## Tests (AppUITests + unit)
- Unit-test qualityIssuesForJob rules vs fixtures. XCUITest: select issue group, mark reviewed (drops from list), queue re-extraction.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 qualityIssuesForJob rules ported and unit-tested (missing fields, extraction state, short/stale)
- [ ] #2 Issue-grouped lists with severity coloring + site-health metrics
- [ ] #3 Sidebar/dashboard deep-link with issue filter via Router
- [ ] #4 Batch mark-reviewed/clear/queue-extraction/open-sources via JobService
- [ ] #5 XCUITest covers review + queue actions
<!-- AC:END -->
