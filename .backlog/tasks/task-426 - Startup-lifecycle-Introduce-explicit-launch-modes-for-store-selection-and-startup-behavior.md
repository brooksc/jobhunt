---
id: TASK-426
title: >-
  Startup lifecycle: Introduce explicit launch modes for store selection and
  startup behavior
status: Done
assignee: []
created_date: '2026-06-13 04:33'
updated_date: '2026-06-15 06:30'
labels:
  - audit
  - startup
  - architecture
dependencies: []
references:
  - app/JobhuntApp.swift
modified_files:
  - core/App/LaunchMode.swift
  - app/JobhuntApp.swift
  - tests/CoreTests/LaunchModeTests.swift
priority: high
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
`JobhuntApp.init` currently handles command-line argument parsing, store selection, temporary-store cleanup, production fallback, service wiring, demo seeding, fixture seeding, and process exit in one initializer. Adding or tightening one launch mode risks changing unrelated production startup behavior.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Launch arguments are parsed into an explicit `LaunchMode` or equivalent value before app services are created.
- [x] #2 Store selection, cleanup policy, seeding behavior, fixture generation, and production startup behavior are represented as mode-specific decisions rather than interleaved conditionals.
- [x] #3 Invalid or incomplete launch arguments fail with clear errors instead of silently falling back to production behavior.
- [x] #4 Existing production launch, UI-test launch, fixture-read launch, and fixture-generation launch behavior are preserved except where safer validation is intentionally added.
- [x] #5 Add focused tests for launch-mode parsing and mode-to-startup-plan behavior.
<!-- AC:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Added LaunchMode (production/uiTest/fixtureRead(path)/fixtureGenerate(path)) and LaunchPlan in JobhuntCore, with LaunchPlan.parse(args) called before AppServices is created (AC#1). Store selection, MCP-token need, queue-pause, seeding, and runtime-service decisions are now mode-derived properties (runsRuntimeServices, needsMCPToken, startsQueuePaused, allowsDemoSeed) instead of interleaved conditionals; JobhuntApp uses a per-mode openStore(for:) switch and a single plan-driven init (AC#2). parse() throws LaunchArgumentError on a missing flag value or conflicting mode flags; JobhuntApp surfaces that clearly via StoreRecoveryView instead of falling back to production (AC#3). Existing production/UI-test/fixture-read/fixture-generate behavior preserved, except fixture-generate now correctly skips runtime services and the intentional fail-on-bad-args (AC#4). LaunchModeTests covers parsing, invalid-arg failures, and mode→plan derivations (AC#5). NOTE: GUI app launch/server start not runtime-verified here — recommend a manual smoke launch + AppUITests before release.
<!-- SECTION:FINAL_SUMMARY:END -->
