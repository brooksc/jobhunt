---
id: TASK-136
title: 'Docs: Update contributor test commands for the Swift/Tuist project'
status: Done
assignee: []
created_date: '2026-06-11 03:27'
updated_date: '2026-06-11 20:36'
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

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Updated three files:
- CONTRIBUTING.md: replaced npm-era commands (npm install/start/test/lint) with Swift/Tuist commands. Added fast gate, UI test, and LLM eval sections. Removed Node.js version from issue template.
- scripts/rebuild-and-run.sh: expanded test step from CoreTests-only to the full fast gate (CoreTests + ServerTests + MCPTests), matching CI. Added comment that AppUITests and LLMEval are opt-in pre-release lanes.
- README.md test section was already correct — no changes needed.
<!-- SECTION:FINAL_SUMMARY:END -->
