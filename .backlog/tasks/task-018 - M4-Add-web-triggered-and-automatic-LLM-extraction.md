---
id: TASK-018
title: 'M4: Add web-triggered and automatic LLM extraction'
status: Done
assignee:
  - Codex
created_date: '2026-05-27 06:58'
updated_date: '2026-05-27 07:00'
labels:
  - m4
  - web
  - extraction
dependencies: []
modified_files:
  - src/jobhunt/api.py
  - src/jobhunt/cli.py
  - src/jobhunt/extract.py
  - src/jobhunt/models.py
  - src/jobhunt/static/app.jsx
  - src/jobhunt/static/main.jsx
  - src/jobhunt/static/screens/dashboard.jsx
  - tests/test_api.py
  - tests/test_extract.py
priority: high
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Add a functional web control to process pending job extractions and automatically attempt extraction after new Chrome extension captures. Extraction should reuse the existing LM Studio/OpenAI-compatible pipeline and keep capture requests responsive.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 The web interface includes a visible action to process all pending or failed extractions and refreshes the UI with results.
- [x] #2 The server exposes an API endpoint that runs extraction for outstanding jobs and returns processed succeeded and failed counts.
- [x] #3 New captures from the Chrome extension enqueue extraction automatically without delaying the capture response on LLM latency.
- [x] #4 Default LM Studio configuration uses the local server URL that works with the user's setup unless overridden by environment variables.
- [x] #5 Automated tests cover the extraction API endpoint and automatic capture-triggered extraction behavior without calling a real LLM.
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. Add an extraction runner hook to the FastAPI app state so tests can inject a fake extractor while production uses LMStudioExtractor.
2. Add POST /api/extractions/run to process pending/failed jobs and return the existing ExtractionSummary counts.
3. Schedule a one-item background extraction after successful non-duplicate captures so extension saves remain fast while new jobs are processed automatically.
4. Change the default LM Studio base URL to http://127.0.0.1:1234 while preserving environment/CLI overrides.
5. Wire a visible Process pending action in the dashboard/jobs topbar to call the endpoint and refresh.
6. Add focused tests for manual extraction and capture-triggered background extraction using a fake extractor, then run the suite.
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Implemented extraction processing as a test-injectable FastAPI runner. Production serve paths enable auto_extract, while create_app defaults to auto_extract=False so tests and other embedding code do not accidentally call LM Studio. Manual /api/extractions/run processes up to 100 pending/failed records; capture-triggered background extraction processes one new non-duplicate capture.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Added M4 extraction processing from the web UI and capture flow. The server now exposes POST /api/extractions/run returning processed/succeeded/failed counts, and production server creation enables background extraction after successful non-duplicate captures. The web UI has a visible Process pending action on the Jobs and Dashboard top bars plus an extraction card action. The LM Studio default base URL now matches the local setup at http://127.0.0.1:1234 while preserving environment and CLI overrides. Tests cover manual extraction and automatic capture-triggered extraction with a fake extractor, avoiding real LLM calls.

Verification: .venv/bin/python -m pytest -> 36 passed; .venv/bin/python -m compileall src/jobhunt -> passed.
<!-- SECTION:FINAL_SUMMARY:END -->
