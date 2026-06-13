---
id: TASK-426
title: >-
  Startup lifecycle: Introduce explicit launch modes for store selection and
  startup behavior
status: To Do
assignee: []
created_date: '2026-06-13 04:33'
labels:
  - audit
  - startup
  - architecture
dependencies: []
references:
  - app/JobhuntApp.swift
priority: high
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
`JobhuntApp.init` currently handles command-line argument parsing, store selection, temporary-store cleanup, production fallback, service wiring, demo seeding, fixture seeding, and process exit in one initializer. Adding or tightening one launch mode risks changing unrelated production startup behavior.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Launch arguments are parsed into an explicit `LaunchMode` or equivalent value before app services are created.
- [ ] #2 Store selection, cleanup policy, seeding behavior, fixture generation, and production startup behavior are represented as mode-specific decisions rather than interleaved conditionals.
- [ ] #3 Invalid or incomplete launch arguments fail with clear errors instead of silently falling back to production behavior.
- [ ] #4 Existing production launch, UI-test launch, fixture-read launch, and fixture-generation launch behavior are preserved except where safer validation is intentionally added.
- [ ] #5 Add focused tests for launch-mode parsing and mode-to-startup-plan behavior.
<!-- AC:END -->
