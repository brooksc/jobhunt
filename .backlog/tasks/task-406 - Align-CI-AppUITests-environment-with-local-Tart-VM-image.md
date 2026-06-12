---
id: TASK-406
title: Align CI AppUITests environment with local Tart VM image
status: To Do
assignee: []
created_date: '2026-06-12 23:54'
labels: []
dependencies: []
priority: low
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
`.github/workflows/ui-tests.yml` runs on `macos-latest`, which gets a different Xcode and macOS patch version than the local Tart VM image. Tests can pass locally but behave differently in CI.

Evaluate: (1) Use `cirruslabs/tart-action` in CI to run the same pinned Tart image, or (2) pin both environments to the same Xcode version via `xcode-select`. At minimum, document the exact Xcode version each environment uses and add a check that alerts when they drift.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 CI AppUITests run against the same Xcode version as the local Tart VM, OR the divergence is explicitly documented with version numbers in both places
<!-- AC:END -->
