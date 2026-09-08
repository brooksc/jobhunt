---
id: TASK-697
title: >-
  Extension's app-focus fallback opens a dead tab — it still targets the deleted
  React web UI
status: Done
assignee: []
created_date: '2026-08-31 18:38'
updated_date: '2026-09-08 17:05'
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
- [x] #1 The focus fallback no longer opens a URL the Swift server does not serve
- [x] #2 When the app is unreachable the user gets an actionable signal (badge/message) telling them to launch Jobhunt
- [x] #3 Behaviour matches how the extension surfaces other unreachable-server states
- [x] #4 The stale 'or Electron not responding' comment is corrected
- [x] #5 Covered by a test in extension/tests/
<!-- AC:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Fixed in 9d0f0d12. The fallback now shows the ERR badge, sets the action title to "JobHunt isn't running — open the Mac app to continue.", and opens the extension's own `status.html`.

That page was the right answer rather than a new one: it always loads (extension-owned, not served by the app), it already explains this exact state — what still works without the Mac app, plus the opt-in auto-launch setting — and it is the same surface the offline-capture path uses, so "the app isn't running" looks identical however the user meets it (AC#3). `background: false` skips the anti-spam throttle and focuses an already-open tab, which is right for an explicit user action.

**No new manifest permission.** `chrome.notifications` was the obvious way to message the user, but adding a permission triggers Chrome Web Store re-review and re-consent from every installed user — disproportionate here, and it would also break the Firefox manifest parity test.

**Testing (AC#5): four behaviour tests in `extension/tests/test_open_app_fallback.js`**, driving the worker with a stubbed `fetch` rather than grepping the source — a string match passes whether or not the branch is reachable, which is the failure mode this area keeps producing. Each was verified to fail against the old code before being kept: 4 fail against the bug, 4 pass against the fix.

Worth recording: the first draft of the first test was **decorative**. It asserted no `http://` tab is opened, and passed against the buggy code too — because with every port probe failing, `serverUrl()` throws before the old code could open its tab. Rewritten so the port resolves and only `/api/app/focus` fails, which is the real shape of the failure (the server answers; focus does not). That version does catch it.

Full extension suite: 145 pass / 0 fail. `chromestore/jobhunt-capture-1.5.0.zip` repackaged so the shipped artifact carries the fix.
<!-- SECTION:FINAL_SUMMARY:END -->
