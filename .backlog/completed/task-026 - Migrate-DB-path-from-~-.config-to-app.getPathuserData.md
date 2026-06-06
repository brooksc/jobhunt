---
id: TASK-026
title: Migrate DB path from ~/.config to app.getPath('userData')
status: Done
assignee: []
created_date: '2026-06-06 22:38'
updated_date: '2026-06-06 22:48'
labels:
  - electron
  - data
milestone: m-0
dependencies: []
modified_files:
  - electron/main.js
  - tests/electron/smoke.test.js
priority: high
ordinal: 1000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
## Problem

`electron/main.js` currently hardcodes the database path as:

```js
path.join(os.homedir(), '.config', 'jobhunt', 'jobhunt.db')
```

This path is outside the App Sandbox container and will be inaccessible to the Mac App Store build. Under App Sandbox, apps can only read/write their designated container at `~/Library/Containers/com.jobhunt-app.jobhunt/`. The fix is to use Electron's `app.getPath('userData')`, which automatically resolves to the correct platform path for each distribution channel:

- **GitHub DMG (unsandboxed):** `~/Library/Application Support/Jobhunt/jobhunt.db`
- **Mac App Store (sandboxed):** `~/Library/Containers/com.jobhunt-app.jobhunt/Data/Library/Application Support/Jobhunt/jobhunt.db`

## Implementation

In `electron/main.js`, `startServer()` function (around line 220):

**Before:**
```js
const dbPath = process.env.JOBHUNT_DB_PATH
  || path.join(os.homedir(), '.config', 'jobhunt', 'jobhunt.db');
```

**After:**
```js
const dbPath = process.env.JOBHUNT_DB_PATH
  || path.join(app.getPath('userData'), 'jobhunt.db');
```

Also ensure the directory is created before `initDb` is called (in case it's a fresh install):

```js
import { mkdirSync } from 'node:fs';
// ...
const dbDir = path.dirname(dbPath);
mkdirSync(dbDir, { recursive: true });
```

Remove the `os` import if it's no longer used anywhere else in the file (check first — it may be used elsewhere).

## Data Migration (brooksc only — no other users)

The developer's data lives at `~/.config/jobhunt/jobhunt.db`. After shipping this change, run:

```bash
mkdir -p ~/Library/Application\ Support/Jobhunt
cp ~/.config/jobhunt/jobhunt.db ~/Library/Application\ Support/Jobhunt/jobhunt.db
```

No migration code needed in the app itself.

## Important: Keep JOBHUNT_DB_PATH override

The `JOBHUNT_DB_PATH` environment variable override must be preserved. It's used by the integration test suite (`tests/integration/`) to point each test at an isolated temp database. Without it, tests would clobber the real database.

## Verification

- `npm run electron` — app launches and finds its database at the new path
- `JOBHUNT_DB_PATH=/tmp/test.db npm run electron` — override still works
- `npm test` — all existing tests still pass (they use `JOBHUNT_DB_PATH` / `tempDbPath()`)
- Confirm no remaining hardcoded references to `~/.config/jobhunt` in `electron/` directory
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 app.getPath('userData') is used as the default DB path in startServer()
- [x] #2 JOBHUNT_DB_PATH environment variable override still takes precedence
- [x] #3 The userData directory is created with mkdirSync({ recursive: true }) before initDb is called
- [x] #4 os import is removed if no longer used
- [x] #5 npm test passes with no failures
- [x] #6 App launches successfully and loads existing data at the new path after manual data copy
<!-- AC:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Switched DB path from `path.join(os.homedir(), '.config', 'jobhunt', 'jobhunt.db')` to `path.join(app.getPath('userData'), 'jobhunt.db')` in `electron/main.js`. Added `mkdirSync({ recursive: true })` to ensure the directory exists on fresh installs. Removed the `os` import; added `mkdirSync` from `node:fs`. Updated the smoke test assertion to check for `app.getPath('userData')` instead of the old hardcoded path. Data manually copied from `~/.config/jobhunt/jobhunt.db` to `~/Library/Application Support/Jobhunt/jobhunt.db` (both old and new target backed up with timestamp before migration). All 454 tests pass.
<!-- SECTION:FINAL_SUMMARY:END -->
