---
id: TASK-001
title: Bootstrap local service package and CLI
status: Done
assignee: []
created_date: '2026-05-27 04:35'
updated_date: '2026-05-28 21:43'
labels:
  - m1-foundation
  - server
dependencies: []
modified_files:
  - pyproject.toml
  - main.py
  - src/jobhunt/__init__.py
  - src/jobhunt/api.py
  - src/jobhunt/cli.py
  - tests/test_api.py
priority: high
ordinal: 18000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
probe
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 `uv run jobhunt serve` starts a local HTTP service bound to 127.0.0.1:8765
- [x] #2 `GET /health` returns a JSON response with ok true service jobhunt and version 0.1.0
- [x] #3 `uv run jobhunt --help` shows available commands
- [x] #4 The package layout separates API CLI and tests clearly enough for later capture extraction and export work
- [x] #5 Focused tests cover the health endpoint or equivalent service behavior
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
Implement the M1 foundation in three passes: package/CLI health endpoint, SQLite schema/helpers, then capture ingestion API with tests.
<!-- SECTION:PLAN:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Implemented the Python package and CLI foundation. `uv run jobhunt serve` starts FastAPI on 127.0.0.1:8765, `/health` returns the expected service JSON, and tests cover the health endpoint.
<!-- SECTION:FINAL_SUMMARY:END -->
