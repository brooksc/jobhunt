---
id: TASK-030
title: Add auto-update for GitHub builds via electron-updater
status: To Do
assignee: []
created_date: '2026-06-06 22:42'
labels:
  - electron
  - auto-update
milestone: m-0
dependencies:
  - TASK-029
priority: medium
ordinal: 4000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
## Problem

GitHub DMG users should receive automatic update notifications when a new version is published to GitHub Releases. The Mac App Store build must NOT use this mechanism — MAS handles updates through the store, and calling `autoUpdater` in a sandboxed MAS build will crash.

Electron sets `process.mas = true` when running inside the App Store sandbox. This boolean is the correct guard.

## Implementation

### Install dependency

```bash
npm install electron-updater
```

### `electron/main.js` — add to `app.whenReady()` block

After the window is created and the server is started, add:

```js
// Auto-update: GitHub releases only. MAS builds are updated by the App Store.
if (!process.mas) {
  const { autoUpdater } = await import('electron-updater');
  autoUpdater.checkForUpdatesAndNotify();
}
```

Use a dynamic `import()` so `electron-updater` is never loaded in the MAS module graph. Static imports would cause the module to initialize at startup even inside the MAS sandbox, which causes crashes.

### `package.json` — publish config

Add to the `build` section (task-029 adds this block; add `publish` inside it):

```json
"publish": {
  "provider": "github",
  "owner": "brooksc",
  "repo": "jobhunt"
}
```

This tells `electron-updater` to look for `latest-mac.yml` in the GitHub Releases of `github.com/brooksc/jobhunt`. The CI workflow (task-031) uploads this file automatically when building with `--publish always`.

### Update UX

`checkForUpdatesAndNotify()` is the right level of UX for now:
- Checks silently in the background on launch
- Shows a macOS system notification when an update is ready
- Downloads and stages the update; installs on next app launch
- Does NOT force-restart or interrupt the user

If a more prominent UX is needed later (in-app banner, progress bar), wire up `autoUpdater.on('update-downloaded', ...)` events.

## Dependency

Depends on task-029 (electron-builder dual-target config) which defines the `build` block where `publish` config lives.

## Verification

- `electron-updater` appears in `package.json` dependencies
- `process.mas` is falsy in dev mode (`npm run electron`) — auto-update code path runs without crashing (will fail to fetch update feed since no GitHub Release exists yet — that's expected and handled gracefully)
- `npm test` passes
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 electron-updater is in package.json dependencies
- [ ] #2 electron/main.js calls autoUpdater.checkForUpdatesAndNotify() only when !process.mas
- [ ] #3 The import of electron-updater uses dynamic import() not a static top-level import
- [ ] #4 publish config in package.json build section has provider: github, owner: brooksc, repo: jobhunt
- [ ] #5 npm test passes
<!-- AC:END -->
