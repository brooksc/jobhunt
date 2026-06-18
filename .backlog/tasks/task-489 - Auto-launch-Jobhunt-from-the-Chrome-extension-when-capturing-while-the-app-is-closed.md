---
id: TASK-489
title: >-
  Auto-launch Jobhunt from the Chrome extension when capturing while the app is
  closed
status: To Do
assignee: []
created_date: '2026-06-18 18:53'
labels:
  - extension
  - ux
  - macos
  - feature
dependencies: []
priority: medium
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
- [ ] #1 Capturing while the app is closed launches Jobhunt via the jobhunt:// scheme and the capture syncs once the server is reachable
- [ ] #2 Works on both DMG and MAS builds (scheme launch + localhost flush are sandbox-safe)
- [ ] #3 Behavior is opt-in via a Settings toggle, default off
- [ ] #4 The full capture is sent over localhost HTTP (queue flush), not through the URL
- [ ] #5 App handles jobhunt://launch (brings the app to foreground; no-op otherwise)
<!-- AC:END -->
