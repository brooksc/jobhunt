---
id: TASK-130
title: 'Tests: Run release-risk targets in the normal CI gate'
status: To Do
assignee: []
created_date: '2026-06-11 03:26'
labels:
  - tests
  - ci
  - release-confidence
  - mcp
  - server
dependencies: []
references:
  - Project.swift
  - .github/workflows/swift-build.yml
  - README.md
  - scripts/rebuild-and-run.sh
  - tests/MCPTests/MCPTests.swift
  - tests/ServerTests/JobhuntServerTests.swift
priority: high
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
The current Swift Build workflow builds DMG and MAS but runs only CoreTests on PR/push. Project schemes define MCPTests, AppUITests, and LLMEval targets, but Jobhunt-DMG and Jobhunt-MAS scheme test actions include only CoreTests and ServerTests. Add a clear fast gate for release-risk tests and document slower/manual lanes.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 PR/push CI runs CoreTests, ServerTests, and MCPTests or an explicitly equivalent fast release-risk test command.
- [ ] #2 Jobhunt-DMG scheme membership allows CoreTests, ServerTests, and MCPTests to be selected without scheme errors.
- [ ] #3 AppUITests have a documented scheduled/manual or VM-backed CI lane.
- [ ] #4 LLMEval remains opt-in but has documented prerequisites and pass/fail expectations.
- [ ] #5 README and local scripts name the canonical fast test command and slower confidence commands.
<!-- AC:END -->
