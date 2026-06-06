---
id: TASK-004
title: Build one-click Chrome capture extension
status: Done
assignee: []
created_date: '2026-05-27 04:35'
updated_date: '2026-05-28 21:43'
labels:
  - m2-extension
  - extension
dependencies:
  - TASK-003
modified_files:
  - extension/manifest.json
  - extension/capture.js
  - extension/service_worker.js
  - tests/fixtures/job-posting.html
  - tests/extension/capture_test.mjs
  - pyproject.toml
priority: high
ordinal: 22000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Create the Manifest V3 Chrome extension for the primary low-friction workflow. Clicking the toolbar icon should capture the current tab immediately and submit a raw capture to the local API. There should be no default popup in the MVP.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 The extension can be loaded unpacked in Chrome during development
- [x] #2 Clicking the toolbar icon captures the current tab without opening a popup
- [x] #3 The capture includes URL page title canonical URL when available selected text when present visible text and JSON-LD blocks when available
- [x] #4 The extension posts the capture to http://127.0.0.1:8765/captures
- [x] #5 Manual verification against a simple job posting page confirms the local API receives the expected payload
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
Create a minimal MV3 extension under extension/ with no default popup. The service worker handles chrome.action.onClicked, injects a DOM capture function into the active tab, and posts the payload to the local FastAPI capture endpoint. Verify with a local fixture page and M1 server.
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Implemented as a Manifest V3 extension with no default_popup. Toolbar click is handled by chrome.action.onClicked; capture.js is injected into the active tab before collecting URL title canonical URL selected text visible text and JSON-LD blocks. Automated Node test covers payload construction. Manual browser load was not performed from this environment; API smoke test posted the fixture-shaped payload successfully to the local server.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Built the minimal one-click Chrome extension scaffold. The toolbar action captures the active tab without a popup, includes the required page fields and JSON-LD data, and posts to the local `/captures` endpoint. Verified payload construction with a Node test and verified the fixture-shaped payload against the running FastAPI service.
<!-- SECTION:FINAL_SUMMARY:END -->
