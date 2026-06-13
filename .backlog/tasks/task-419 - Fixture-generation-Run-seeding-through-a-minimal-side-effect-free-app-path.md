---
id: TASK-419
title: 'Fixture generation: Run seeding through a minimal side-effect-free app path'
status: To Do
assignee: []
created_date: '2026-06-13 04:21'
labels:
  - audit
  - fixtures
  - startup
dependencies: []
references:
  - app/JobhuntApp.swift
  - app/Shell/AppServices.swift
  - app/Platform/PlatformIntegration.swift
priority: high
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Fixture generation currently goes through the normal app startup path before seeding and exiting. In `app/JobhuntApp.swift`, `--seed-fixture-output` still constructs `AppServices`, calls `integration.start(queue:)`, and then seeds. `AppServices` starts the local HTTP server, generates/writes the MCP token in non-MAS builds, requeues launch-time work, and runs availability checks; `PlatformIntegration.start` requests notification authorization and registers app integration. Fixture generation should not mutate user-machine state, start user-facing services, or request OS permissions.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Running the fixture-generation command seeds the requested fixture store without starting the local HTTP server, requesting notification authorization, registering focus/deep-link observers, generating/writing MCP tokens, running queue recovery, or running availability checks.
- [ ] #2 Fixture generation exits with a nonzero status and a clear logged error when seeding fails.
- [ ] #3 Normal production app launch, UI-test launch, and `--fixture-db` launch behavior remain unchanged except for intentional fixture-mode isolation.
- [ ] #4 Add or update focused tests or launch-mode coverage that would fail if fixture generation starts normal app services.
<!-- AC:END -->
