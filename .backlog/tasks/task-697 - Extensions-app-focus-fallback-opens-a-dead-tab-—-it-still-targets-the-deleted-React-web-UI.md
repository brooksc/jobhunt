---
id: TASK-697
title: >-
  Extension's app-focus fallback opens a dead tab — it still targets the deleted
  React web UI
status: To Do
assignee: []
created_date: '2026-08-31 18:38'
labels: []
dependencies: []
priority: medium
type: bug
ordinal: 94000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Found in the TASK-696 documentation audit (2026-08-31), but this is shipped code, not a doc problem.

`extension/service_worker.js:778-787`: when `POST /api/app/focus` fails, the fallback is

```js
// Fallback: open the web UI in a browser tab (CLI server or Electron not responding).
const hash = jobNumber ? `#/jobs/${jobNumber}` : "";
const url = await serverUrl("/") + hash;
await chrome.tabs.create({ url, active: true });
```

That `#/jobs/N` route belonged to the **React SPA the Electron app served**, which was deleted in the cutover ([[TASK-064]]). `JobhuntServer` serves nothing at `/` — verified: no `/` route, no static file handler, no `text/html` response anywhere in `server/swift/JobhuntServer.swift`.

So the path that runs precisely when the app is *not* responding opens a blank or errored tab. The user gets a dead tab instead of a usable signal, in the one situation where they most need a clear one. The comment naming Electron is the giveaway that this branch was never revisited.

Correct behaviour is probably the badge-error path the `catch` already uses (`showBadge("ERR", "#b00020")`) plus a message telling the user to launch Jobhunt — the failure is "the app isn't running", and that is worth saying rather than silently opening a tab. Confirm against how the extension surfaces other unreachable-server states so it stays consistent.

Note this is live in the published Chrome Web Store extension, so a fix ships on the extension's own release cycle, not the app's.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 The focus fallback no longer opens a URL the Swift server does not serve
- [ ] #2 When the app is unreachable the user gets an actionable signal (badge/message) telling them to launch Jobhunt
- [ ] #3 Behaviour matches how the extension surfaces other unreachable-server states
- [ ] #4 The stale 'or Electron not responding' comment is corrected
- [ ] #5 Covered by a test in extension/tests/
<!-- AC:END -->
