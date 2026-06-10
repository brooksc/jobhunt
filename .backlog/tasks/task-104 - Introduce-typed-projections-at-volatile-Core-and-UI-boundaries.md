---
id: TASK-104
title: Introduce typed projections at volatile Core and UI boundaries
status: To Do
assignee: []
created_date: '2026-06-10 20:49'
labels:
  - architecture
  - audit
  - core
  - projection
dependencies: []
references:
  - core/Models/Schema.swift
  - core/Models/Job.swift
  - core/LLM/ExtractionEngine.swift
  - app/Views/Detail/JobDetailView.swift
  - server/swift/MCPBridgeRoutes.swift
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Architecture audit finding: `JobhuntCore` intentionally combines domain models with SwiftData persistence models, which is pragmatic for a local-first app but causes persistence shape to leak into UI and adapter behavior. Add typed projection/read-model structs at volatile boundaries so views and adapters stop depending directly on raw SwiftData model shape and raw extracted JSON.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 At least one high-change boundary, preferably job detail display or MCP job detail output, uses a typed projection instead of reading raw SwiftData relationships and JSON in the caller.
- [ ] #2 Projection behavior is tested for missing data, malformed extracted JSON when applicable, and normal populated data.
- [ ] #3 The projection keeps SwiftData model details out of the selected UI or adapter code path.
- [ ] #4 Existing user-visible behavior remains unchanged unless an intentional correction is documented.
<!-- AC:END -->
