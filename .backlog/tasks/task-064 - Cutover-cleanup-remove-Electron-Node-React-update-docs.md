---
id: TASK-064
title: 'Cutover & cleanup: remove Electron/Node/React, update docs'
status: Done
assignee: []
created_date: '2026-06-07 22:51'
updated_date: '2026-06-08 03:55'
labels:
  - swift-rewrite
  - cleanup
  - docs
milestone: m-1
dependencies:
  - TASK-047
  - TASK-048
  - TASK-049
  - TASK-056
  - TASK-059
  - TASK-060
  - TASK-061
  - TASK-062
  - TASK-063
documentation:
  - swift-plan.md
  - README.md
  - CONTRIBUTING.md
priority: medium
ordinal: 4100
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Goal: After the Swift app reaches feature parity and both distribution channels work, remove the legacy stack and update documentation so the repo is Swift-only.

## Read first
- swift-plan.md §17 (deletion list), §15 M9 (cutover), §14 (no in-app migration).
- README.md, CONTRIBUTING.md, docs/ for content that references the Electron/Node stack.

## Implement
- Delete legacy code: electron/, server/ (Node), static/ (React), native/foundation-models/ (subprocess), Electron-specific scripts (scripts/*electron*, scripts/notarize.cjs once replaced, run-server-loop.sh, rebuild-and-launch.sh), and the Electron build config + deps in package.json.
- Keep: extension/ (unchanged), marketing/, chromestore/, .backlog/, test fixtures (reused by Swift tests), bump-version.sh (adapted), swift-plan.md.
- Update README/CONTRIBUTING: Swift/Tuist build + run instructions, MAS+DMG distribution, MCP via jobhunt-mcp, remove Node stack references. Update the "Stack" section.
- Verify the repo builds Swift-only with no dangling references to deleted code.

## Dependencies
Do LAST. Depends on feature-complete app + working distribution: task-047 (server), task-048/049 (Jobs/Detail), task-050–055 (screens), task-056 (settings), task-057 (help), task-059 (mcp), task-060 (platform), task-061 (onboarding), task-062 (DMG dist), task-063 (MAS dist).

## Acceptance / verification
- Legacy directories removed; `tuist generate && xcodebuild build` (both schemes) + full test suite pass with no references to deleted code; docs accurate and Node-free.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Legacy electron/, server/, static/, native/foundation-models/ and Electron scripts/deps removed
- [ ] #2 extension/, fixtures, marketing, chromestore, swift-plan.md retained; bump-version.sh adapted
- [ ] #3 README/CONTRIBUTING updated to Swift/Tuist build+run, MAS+DMG dist, jobhunt-mcp; no Node references
- [ ] #4 Both schemes build + full test suite passes with no dangling references to deleted code
<!-- AC:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Cutover complete: legacy Electron/Node/React stack removed, README and docs updated for native Swift app.
<!-- SECTION:FINAL_SUMMARY:END -->
