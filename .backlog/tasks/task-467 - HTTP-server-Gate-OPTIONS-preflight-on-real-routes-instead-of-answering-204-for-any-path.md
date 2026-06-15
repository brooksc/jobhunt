---
id: TASK-467
title: >-
  HTTP server: Gate OPTIONS preflight on real routes instead of answering 204
  for any path
status: Done
assignee: []
created_date: '2026-06-15 03:38'
updated_date: '2026-06-15 06:33'
labels:
  - bug
  - security
  - server
dependencies: []
references:
  - server/swift/JobhuntServer.swift
priority: high
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
`routeRequest` returns `HTTPResponse.noContent()` for every OPTIONS request before any path or method check (JobhuntServer.swift:390-392), and `processRequest` then attaches CORS headers plus `Access-Control-Allow-Private-Network: true` whenever the origin is allowlisted. Because the preflight never reflects the actually-requested method/path and is identical for real and nonexistent routes, the server tells the browser "any method, any route, private-network access is fine" — independent of the per-route method enforcement tracked separately. The server is loopback-bound so blast radius is limited, but this materially weakens the CORS posture. Fix: only emit a 204 preflight (with Allow-Private-Network) when (Access-Control-Request-Method, path) maps to a real route; otherwise return 404/405 with no CORS.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 OPTIONS to a nonexistent path returns 404/405 with no CORS headers
- [x] #2 OPTIONS preflight succeeds only for (method, path) pairs that map to a real route
- [x] #3 Access-Control-Allow-Private-Network is only sent for valid preflighted routes
- [x] #4 OPTIONS is not short-circuited ahead of the route table
<!-- AC:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Implemented and committed in a8b2338. routeRequest now gates the OPTIONS preflight on isKnownRoute(method:path:) — a 204 + private-network grant is only returned for a real (Access-Control-Request-Method, path) route; unknown routes get 404 with no CORS (processRequest suppresses CORS on a rejected preflight). Tests testCORSPreflight (now sends request-method) + testCORSPreflight_unknownRoute_rejectedWithoutCORS. (Backlog status missed at the time; verified present and marking Done.)
<!-- SECTION:FINAL_SUMMARY:END -->
