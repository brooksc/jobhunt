---
id: TASK-411
title: >-
  Developer workflow: Document a local CI-equivalent gate instead of only the
  partial fast test gate
status: To Do
assignee: []
created_date: '2026-06-13 02:04'
labels:
  - audit
  - developer-workflow
  - ci
  - docs
  - tests
dependencies: []
references:
  - README.md
  - CONTRIBUTING.md
  - .github/workflows/swift-build.yml
  - extension/package.json
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
README and CONTRIBUTING describe CoreTests, ServerTests, and MCPTests as the CI-matching fast gate, but the normal CI also builds DMG and MAS schemes, runs extension Node tests, SwiftLint, and SwiftFormat. Add a documented local command or checklist that matches the full CI gate, while keeping the fast gate clearly labeled as partial.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Docs distinguish the partial fast test gate from the full CI-equivalent gate.
- [ ] #2 A local CI-equivalent command or checklist includes DMG build, MAS build, Core/Server/MCP tests, extension tests, SwiftLint, and SwiftFormat.
- [ ] #3 Contributor docs explain when to run the fast gate versus the full gate.
- [ ] #4 The documented full gate matches `.github/workflows/swift-build.yml` or explicitly notes intentional differences.
<!-- AC:END -->
