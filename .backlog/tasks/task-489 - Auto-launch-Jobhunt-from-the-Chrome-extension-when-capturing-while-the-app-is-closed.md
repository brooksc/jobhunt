---
id: TASK-489
title: >-
  Auto-launch Jobhunt from the Chrome extension when capturing while the app is
  closed
status: Done
assignee: []
created_date: '2026-06-18 18:53'
updated_date: '2026-08-10 01:36'
labels:
  - extension
  - ux
  - macos
  - feature
dependencies: []
modified_files:
  - extension/launch_app.js
  - extension/service_worker.js
  - extension/status.html
  - extension/status.js
  - extension/package.json
  - extension/tests/test_launch_app.js
  - app/Platform/PlatformIntegration.swift
priority: medium
ordinal: 3000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
When the user captures a job and the app isn't running, the extension should start the app and then resend the capture once the local server is reachable, instead of just queuing it for a manual later sync.

Chosen approach (works for BOTH DMG and MAS): the `jobhunt://` custom URL scheme. It's already registered (Project.swift CFBundleURLTypes) and the deep-link handler exists (PlatformIntegration.handleDeepLink). Registering/receiving a URL scheme and being launched via it are all sandbox-safe, and the MAS build already runs the localhost capture server (it's not behind #if !MAS_BUILD and MAS has com.apple.security.network.server), so the queued capture can flush over HTTP after launch.

Flow: on capture, if /api/ping fails → queue the capture (already built: retry_queue.js / flushCaptureQueue) → open `jobhunt://launch` to start the app → poll /api/ping for a few seconds → flush the queue when reachable.

Scope/notes:
- Use the scheme only to LAUNCH; send the real capture over the existing localhost HTTP queue-flush (captures are up to 4 MB — too big for a URL).
- Chrome shows a one-time "Open Jobhunt?" external-protocol confirmation; the user ticks "Always allow". This is accepted (a browser security gate that extensions can't bypass).
- Make it opt-in via a Settings toggle ("Launch Jobhunt automatically when capturing").
- Add `jobhunt://launch` handling (a no-op deep link that just brings the app up is sufficient).
- DMG-only promptless alternative (NOT this task): a Native Messaging host (loose helper + manifest in ~/Library/.../NativeMessagingHosts) would avoid the Chrome prompt but cannot work in MAS (can't install the manifest outside the sandbox). Document as a future DMG-only upgrade.

References: extension/service_worker.js, extension/retry_queue.js, app/Platform/PlatformIntegration.swift (handleDeepLink), Project.swift (CFBundleURLTypes).
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 not verified: (visual) — the end-to-end launch needs a real Chrome plus a quit app, which means driving the UI. The launch/poll/flush logic, the cooldown and the failure paths are unit-tested; the app's jobhunt://launch handling is compile-checked.
- [x] #2 Works on both DMG and MAS builds (scheme launch + localhost flush are sandbox-safe)
- [x] #3 Behavior is opt-in via a Settings toggle, default off
- [x] #4 The full capture is sent over localhost HTTP (queue flush), not through the URL
- [x] #5 App handles jobhunt://launch (brings the app to foreground; no-op otherwise)
<!-- AC:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
`extension/launch_app.js` opens `jobhunt://launch`, polls `/api/ping` for up to 12s, and the service worker flushes the queue when the app answers.

#4 The scheme carries **nothing but the launch** — a capture can be several MB and a URL can't be — so the capture still goes over localhost HTTP. A test asserts the URL has no query string, since that's the property that would quietly erode.

#5 `PlatformIntegration.handleDeepLink` now handles `jobhunt://launch` by activating; the guard was restructured so a non-`jobs` host is no longer silently dropped.

#2 Nothing here is DMG-only: registering and receiving a URL scheme is sandbox-safe and the MAS build already runs the capture server.

#3 Off by default, with a toggle on the extension's status page.

**Ordering decision:** queue first, launch second. If the launch fails the capture is already stored, rather than the capture depending on the launch surviving. A launch timeout is likewise *not* an error — the capture is queued, which is exactly the previous behaviour.

**Cooldown, 30s:** without it, capturing three jobs in a row with the app shut fires three `jobhunt://` opens and Chrome shows its external-protocol prompt for each. Injected clock, so the cooldown is tested without waiting.

#1 rewritten `not verified: (visual)` — proving the end-to-end launch needs a real Chrome and a quit app, i.e. driving the UI, which is out of bounds here.

10 extension tests (116 total pass). Gate: fast gate TEST SUCCEEDED, swiftlint 0 violations in 359 files, swiftformat clean, `npm test` 116/116.
<!-- SECTION:FINAL_SUMMARY:END -->
