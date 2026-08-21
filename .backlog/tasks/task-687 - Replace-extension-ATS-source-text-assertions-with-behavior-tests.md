---
id: TASK-687
title: Replace extension ATS source-text assertions with behavior tests
status: To Do
assignee: []
created_date: '2026-08-21 20:42'
labels:
  - extension
  - tests
  - tech-debt
dependencies: []
references:
  - extension/tests/test_greenhouse_timeout.js
  - extension/tests/test_ats_enrichment.js
  - extension/service_worker.js
priority: medium
type: chore
ordinal: 61000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Several extension tests validate ATS and Greenhouse enrichment by reading implementation source and matching strings or textual call order. Replace those implementation-coupled checks with behavior-level contracts so safe refactors do not fail tests and unreachable wiring cannot pass merely because expected text remains in the file.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Greenhouse timeout tests invoke executable behavior with controlled fetch and clock dependencies
- [ ] #2 ATS enrichment tests verify capture inputs and outputs rather than source substrings or textual call order
- [ ] #3 Tests prove timeout cleanup, failure fallback, host permission requirements, enrichment ordering where behaviorally relevant, and structured-data synchronization
- [ ] #4 The converted tests do not read service_worker.js to inspect function bodies or use source includes checks
- [ ] #5 A regression in capture-to-enrichment wiring causes the behavior suite to fail
- [ ] #6 All extension tests pass with no reduction in the behaviors currently covered
<!-- AC:END -->
