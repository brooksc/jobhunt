---
id: TASK-419
title: 'Fixture generation: Run seeding through a minimal side-effect-free app path'
status: Done
assignee: []
created_date: '2026-06-13 04:21'
updated_date: '2026-06-15 06:38'
labels:
  - audit
  - fixtures
  - startup
dependencies: []
references:
  - app/JobhuntApp.swift
  - app/Shell/AppServices.swift
  - app/Platform/PlatformIntegration.swift
modified_files:
  - app/JobhuntApp.swift
  - core/App/LaunchMode.swift
priority: high
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Fixture generation currently goes through the normal app startup path before seeding and exiting. In `app/JobhuntApp.swift`, `--seed-fixture-output` still constructs `AppServices`, calls `integration.start(queue:)`, and then seeds. `AppServices` starts the local HTTP server, generates/writes the MCP token in non-MAS builds, requeues launch-time work, and runs availability checks; `PlatformIntegration.start` requests notification authorization and registers app integration. Fixture generation should not mutate user-machine state, start user-facing services, or request OS permissions.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Running the fixture-generation command seeds the requested fixture store without starting the local HTTP server, requesting notification authorization, registering focus/deep-link observers, generating/writing MCP tokens, running queue recovery, or running availability checks.
- [x] #2 Fixture generation exits with a nonzero status and a clear logged error when seeding fails.
- [x] #3 Normal production app launch, UI-test launch, and `--fixture-db` launch behavior remain unchanged except for intentional fixture-mode isolation.
- [x] #4 Add or update focused tests or launch-mode coverage that would fail if fixture generation starts normal app services.
<!-- AC:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Fixture-generate mode (LaunchPlan.runsRuntimeServices == false) now skips BOTH services.startRuntime() (server/MCP-token/queue-recovery/availability, via TASK-425) AND integration.start() (notification authorization, focus/deep-link observers, window policy) — so --seed-fixture-output only seeds and exits with no user-machine side effects (AC#1). Seeding failure exits nonzero with a logged error (AC#2, pre-existing). Production/UI-test/--fixture-db unchanged (AC#3). LaunchModeTests.testFixtureGenerateOptsOutOfRuntimeServicesAndToken asserts the mode→no-runtime-services decision (AC#4).
<!-- SECTION:FINAL_SUMMARY:END -->
