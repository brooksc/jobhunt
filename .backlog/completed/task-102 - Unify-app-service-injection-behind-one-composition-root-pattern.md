---
id: TASK-102
title: Unify app service injection behind one composition-root pattern
status: Done
assignee: []
created_date: '2026-06-10 20:49'
updated_date: '2026-06-11 01:43'
labels:
  - architecture
  - audit
  - dependency-injection
dependencies: []
references:
  - app/JobhuntApp.swift
  - app/Shell/AppServices.swift
  - app/Views/Detail/ServiceEnvironmentKeys.swift
  - app/Views/Jobs/AddJobSheet.swift
  - app/Views/Detail/JobDetailView.swift
  - app/ContentView.swift
priority: high
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Architecture audit finding: `JobhuntApp` injects `AppServices` into the SwiftUI environment, while many views read separate optional `jobService` and `queueActor` environment keys that are not visibly wired at the root. This can make actions silently no-op when a view uses the optional service key instead of `AppServices`. Choose one app-wide service injection rule and apply it consistently.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 All SwiftUI views access `JobService` and `QueueActor` through one consistent app-wide injection pattern.
- [ ] #2 Service access used by production views is non-optional or explicitly fails loudly when missing rather than silently skipping work.
- [ ] #3 `AddJobSheet` successfully creates or reports failure for valid input through the wired service path.
- [ ] #4 Tests or previews that need service injection are updated to use the selected pattern.
<!-- AC:END -->
