---
id: TASK-136
title: 'Docs: Update contributor test commands for the Swift/Tuist project'
status: To Do
assignee: []
created_date: '2026-06-11 03:27'
labels:
  - documentation
  - tests
  - developer-experience
dependencies: []
references:
  - CONTRIBUTING.md
  - README.md
  - scripts/rebuild-and-run.sh
  - .github/workflows/swift-build.yml
priority: low
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Developer docs still reference npm-era commands or CoreTests-only commands. Update the contributor and README guidance to match the current Swift/Tuist project and the desired fast/release-confidence test lanes.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 CONTRIBUTING.md no longer tells Swift contributors to run npm test/npm lint for the current app workflow.
- [ ] #2 README documents the fast test command that matches CI.
- [ ] #3 README or scripts document how to run ServerTests, MCPTests, AppUITests, and LLMEval where appropriate.
- [ ] #4 Local helper scripts do not imply CoreTests-only is sufficient for release confidence.
<!-- AC:END -->
