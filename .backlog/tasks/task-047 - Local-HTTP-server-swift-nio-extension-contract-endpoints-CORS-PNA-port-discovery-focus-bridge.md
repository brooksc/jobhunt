---
id: TASK-047
title: >-
  Local HTTP server (swift-nio): extension contract endpoints, CORS/PNA, port
  discovery, focus bridge
status: To Do
assignee: []
created_date: '2026-06-07 22:48'
labels:
  - swift-rewrite
  - server
milestone: m-1
dependencies:
  - TASK-046
documentation:
  - swift-plan.md
  - server/api.js
  - extension/service_worker.js
  - extension/capture.js
  - tests/integration/api.test.js
priority: high
ordinal: 2400
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Goal: Implement the in-process localhost HTTP server that the (unchanged) Chrome extension talks to. With the SwiftUI frontend calling services in-process, this server only needs the 5 extension endpoints + health + the window-focus bridge.

## Read first
- swift-plan.md §4 (the extension contract table — exact request/response shapes), §7 (server scope, CORS/PNA, port discovery, focus bridge), §2 (only extension endpoints stay HTTP).
- Legacy extension/service_worker.js + extension/capture.js — confirm the exact payloads/headers the extension sends (capture payload fields, port probe over 8765–8769, /api/ping discovery, chrome-extension origin).
- Legacy server/api.js — the 5 endpoints: GET /api/ping, POST /captures, POST /site-reviews, GET /api/jobs/by-url, POST /api/app/focus; and the CORS handling incl. Access-Control-Allow-Private-Network.
- tests/integration/api.test.js (CORS/PNA + capture assertions).

## Implement (server/swift/, JobhuntServer target)
- swift-nio NIOHTTP1 listener bound to 127.0.0.1; try ports 8765→8769 in order, expose the chosen port to the app.
- Minimal router for: GET /health, GET /api/ping ({app,version,isDemo}), POST /captures (decode payload → JobService.ingestCapture → {ok,capture_id,job_number,duplicate}), POST /site-reviews (→ SiteService → {ok,site_review_id}), GET /api/jobs/by-url?url= ({job_number} or 400), POST /api/app/focus ({job_number?} → post a focus/navigate notification the app observes).
- CORS middleware: handle OPTIONS preflight for chrome-extension:// origins, set Access-Control-Allow-Private-Network: true, allow Content-Type.
- Capture validation parity (require url, page_title, and one of visible_text/selected_text).
- Lifecycle: start after the ModelContainer is ready; graceful shutdown on app terminate.
- Stub the DMG-only MCP-bridge endpoints behind `#if !MAS_BUILD` (full impl in the MCP task); leave a clear extension point.

## Dependencies
Depends on task-046 (JobService/SiteService). The focus bridge is consumed by platform integration (task R). Validated under MAS sandbox in the MAS distribution task.

## Tests (ServerTests)
- Spin the listener on an ephemeral port; POST a fixture capture → Job created with correct job_number + response shape; duplicate handling; /api/ping shape; by-url found/404; OPTIONS preflight returns the PNA + CORS headers. Port the relevant api.test.js cases.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 NIO server binds 127.0.0.1, probes 8765–8769 in order, exposes chosen port
- [ ] #2 All 5 extension endpoints + /health implemented with byte-compatible request/response shapes (§4)
- [ ] #3 OPTIONS preflight returns Access-Control-Allow-Private-Network + CORS headers for chrome-extension origins
- [ ] #4 Capture validation parity; ingestion creates a Job and returns correct shape
- [ ] #5 /api/app/focus posts a focus/navigate notification consumed by the app
- [ ] #6 Real Chrome extension can capture into the running app end-to-end; ported api.test.js cases pass
<!-- AC:END -->
