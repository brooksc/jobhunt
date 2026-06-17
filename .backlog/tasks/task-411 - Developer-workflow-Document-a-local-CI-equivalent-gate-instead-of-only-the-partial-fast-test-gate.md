---
id: TASK-411
title: >-
  Developer workflow: Document a local CI-equivalent gate instead of only the
  partial fast test gate
status: Done
assignee: []
created_date: '2026-06-13 02:04'
updated_date: '2026-06-17 04:57'
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
- [x] #1 Docs distinguish the partial fast test gate from the full CI-equivalent gate.
- [x] #2 A local CI-equivalent command or checklist includes DMG build, MAS build, Core/Server/MCP tests, extension tests, SwiftLint, and SwiftFormat.
- [x] #3 Contributor docs explain when to run the fast gate versus the full gate.
- [x] #4 The documented full gate matches `.github/workflows/swift-build.yml` or explicitly notes intentional differences.
<!-- AC:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Corrected the misleading "fast gate matches CI" claim in README + CONTRIBUTING. The fast gate (Core+Server+MCP) is now labeled a PARTIAL quick-feedback check (AC#1). CONTRIBUTING gains a "Full CI-equivalent gate" block that mirrors .github/workflows/swift-build.yml step-for-step (AC#2/#4): mise install → tuist generate → DMG build → MAS build → fast tests + check-coverage.sh floor → npm test --prefix extension → swiftlint --strict → swiftformat --lint, with the mixed-case-path and fixture-manifest guards noted as conditional and AppUITests called out as in neither gate. Both docs explain when to run each — fast while iterating, full before a PR (AC#3). README links to the CONTRIBUTING section.
<!-- SECTION:FINAL_SUMMARY:END -->
