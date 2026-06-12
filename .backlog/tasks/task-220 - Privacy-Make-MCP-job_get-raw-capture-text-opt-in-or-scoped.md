---
id: TASK-220
title: 'Privacy: Make MCP job_get raw capture text opt-in or scoped'
status: Done
assignee: []
created_date: '2026-06-12 01:06'
updated_date: '2026-06-12 02:00'
labels:
  - privacy
  - mcp
  - api
dependencies: []
references:
  - server/swift/MCPBridgeRoutes.swift
  - core/Models/Projections.swift
  - tests/CoreTests/ModelRoundTripTests.swift
priority: medium
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
MCP job_get returns selected_text and visible_text by default. Add a least-privilege mode so metadata can be fetched without raw captured page text, and require an explicit flag or separate scoped endpoint for raw text.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Default MCP job_get response omits or redacts raw selected_text and visible_text, or a documented compatibility decision is made.
- [ ] #2 A deliberate include_raw_text flag or scoped endpoint returns raw text when needed.
- [ ] #3 MCP documentation and tests reflect the raw-text behavior.
- [ ] #4 Existing agent workflows that need raw job text have a clear migration path.
<!-- AC:END -->
