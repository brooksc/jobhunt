---
id: TASK-619
title: Create Safari and Firefox JobHunt capture extensions
status: To Do
assignee: []
created_date: '2026-07-22 20:01'
labels:
  - extension
  - safari
  - firefox
  - integration
  - release
dependencies: []
references:
  - extension/manifest.json
  - extension/service_worker.js
  - extension/capture.js
  - extension/retry_queue.js
  - extension/status.html
  - extension/status.js
  - extension/note.html
  - extension/note.js
  - extension/package.json
  - extension/tests/test_service_worker_contract.js
  - server/swift/JobhuntServer.swift
  - server/swift/MCPBridgeRoutes.swift
  - core/App/ServerPortContract.swift
  - Project.swift
  - README.md
  - CLAUDE.md
priority: high
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Extend JobHunt Capture to Safari and Firefox while keeping one shared capture implementation across Chrome, Safari, and Firefox. Do not fork three copies of capture parsing, payload construction, offline queueing, status handling, or local-server discovery.

## Architecture
Refactor the existing Chrome extension into a shared WebExtension core plus thin browser-specific adapters and manifests. Introduce a small compatibility boundary for `chrome`/`browser` namespaces and APIs that differ or are unavailable, including background lifecycle, `storage.session`, script injection, context menus, downloads, badges, commands, tab/window handling, and runtime URLs. Preserve the existing payload and Swift server contracts.

Keep Chrome behavior and store packaging unchanged. Produce:
- A Safari Web Extension embedded in the native JobHunt macOS app using project/Tuist targets, entitlements, signing, and bundle identifiers appropriate to the existing release channels.
- A Firefox WebExtension with its own manifest metadata, stable Gecko add-on ID, permissions, build/package output, and AMO-ready signed/distribution workflow.

## Functional parity
Both new extensions should support one-click capture, the capture keyboard command, relevant context-menu actions, Save with Note, selected/full-page text capture, structured-data and Greenhouse enrichment, Readability cleanup, port discovery, local submission, duplicate/open-in-app behavior, offline queue/retry, status/badge feedback, queue inspection/export/clear, privacy notices, and actionable errors. Where a browser cannot support an exact Chrome interaction, provide the smallest equivalent workflow and document the difference rather than silently omitting it.

## Local-server security
Audit the current Chrome-extension origin allowlist, CORS/PNA behavior, and launch/focus bridge for Safari and Firefox extension origins. Add narrowly scoped trusted-origin/pairing behavior for the actual installed extensions with regression tests. Do not solve Firefox’s potentially installation-specific `moz-extension` origin by allowing arbitrary extension origins or weakening loopback-only/network boundaries. Keep capture routes interoperable with all supported browsers and preserve existing security behavior.

## Packaging and product integration
Add reproducible development and release build commands for Chrome zip, Firefox package/XPI submission artifact, and the Safari-containing app. Integrate version parity, release checks, signing/notarization/store metadata, privacy disclosures, permission rationales, and checksums/provenance with existing workflows. Update onboarding, Settings extension status/install links, README/help, website links, and troubleshooting so users choose Chrome, Firefox, or Safari and know that the JobHunt app must be running unless queued offline.

Use temporary test data and the local Swift server. Do not mutate production data, add a second backend protocol, or introduce dependencies unless needed for a browser compatibility/build boundary.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Chrome, Firefox, and Safari builds consume one shared capture/payload/queue implementation with only thin browser-specific API adapters and manifests.
- [ ] #2 The existing Chrome extension retains current behavior and its regression suite remains passing.
- [ ] #3 Firefox supports toolbar capture, keyboard capture, applicable context-menu actions, Save with Note, structured/full-text capture, local port discovery, offline retry, status feedback, and queue management.
- [ ] #4 A Firefox manifest/package includes a stable Gecko add-on identity, least-privilege permissions, version metadata, icons, and a reproducible AMO-ready artifact/signing workflow.
- [ ] #5 A Safari Web Extension target is embedded in the JobHunt macOS app and builds with the required bundle identifiers, entitlements, signing, and release packaging.
- [ ] #6 Safari supports the same core capture, note, local submission, offline retry, and status workflows, with documented equivalent UX for any unsupported WebExtension API.
- [ ] #7 All browsers submit the same versioned capture contract to the existing Swift server and preserve structured data, canonical URL, selected/visible text, notes, and extension version.
- [ ] #8 Port discovery across 127.0.0.1:8765-8769, app-not-running behavior, queued retry, and reconnect/flush behavior work in Safari and Firefox.
- [ ] #9 Server origin/CORS/PNA validation recognizes only the intended Chrome, Safari, and Firefox extensions without allowing arbitrary extension origins or weakening loopback and existing authentication boundaries.
- [ ] #10 Browser-specific fallbacks cover unavailable or differing background lifecycle, session storage, script injection, context-menu, downloads, badge, command, and tab APIs without data loss.
- [ ] #11 Automated shared-core and adapter contract tests run in CI, and end-to-end tests capture a representative posting from both Firefox and Safari into a temporary JobHunt database.
- [ ] #12 Release automation produces the existing Chrome artifact, a Firefox submission/distribution artifact, and a signed/notarized JobHunt app containing the Safari extension, with version-parity checks.
- [ ] #13 Store/privacy documentation explains requested permissions, locally captured page content, offline retention/export, Greenhouse enrichment, and communication with the loopback JobHunt server for each browser.
- [ ] #14 Onboarding, Settings, README/help, website install links, and troubleshooting expose all three supported browsers without claiming installation or connectivity that has not been detected.
- [ ] #15 Manual verification covers LinkedIn and at least two ATS-hosted postings, selected-text capture, Save with Note, app offline/online recovery, duplicate capture, restricted pages, and browser restart for Safari and Firefox.
<!-- AC:END -->
