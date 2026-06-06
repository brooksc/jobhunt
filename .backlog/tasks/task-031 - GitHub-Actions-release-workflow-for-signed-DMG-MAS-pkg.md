---
id: TASK-031
title: GitHub Actions release workflow for signed DMG + MAS pkg
status: Done
assignee: []
created_date: '2026-06-06 22:42'
updated_date: '2026-06-06 23:11'
labels:
  - ci
  - release
  - signing
milestone: m-0
dependencies:
  - TASK-029
modified_files:
  - .github/workflows/release.yml
  - scripts/notarize.cjs
  - package.json
  - package-lock.json
priority: medium
ordinal: 5000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
## Problem

There is no CI/CD pipeline. Releases require manual local builds with locally-stored signing certificates. Two automated release jobs are needed:

1. **DMG job** — builds, signs with Developer ID, notarizes via Apple notary service, uploads to GitHub Releases (this also publishes `latest-mac.yml` which powers auto-update for existing users)
2. **MAS job** — builds a signed `.pkg`, uploads as a GitHub Actions workflow artifact for manual submission to App Store Connect via Transporter

Both jobs trigger on `push: tags: ['v*']` (e.g., `v1.2.3`).

## Implementation

### Create `.github/workflows/release.yml`

```yaml
name: Release

on:
  push:
    tags:
      - 'v*'

# Required secrets (configure in repo Settings > Secrets > Actions):
#
# DEVELOPER_ID_CERT_BASE64       — "Developer ID Application" cert exported as .p12, base64-encoded
# DEVELOPER_ID_CERT_PASSWORD     — Password for the Developer ID .p12
# MAS_CERT_BASE64                — "3rd Party Mac Developer Application" cert as base64-encoded .p12
# MAS_CERT_PASSWORD              — Password for MAS Application .p12
# MAS_INSTALLER_CERT_BASE64      — "3rd Party Mac Developer Installer" cert as base64-encoded .p12
# MAS_INSTALLER_CERT_PASSWORD    — Password for MAS Installer .p12
# APPLE_ID                       — Apple ID email (ai@brooksc.com)
# APPLE_APP_SPECIFIC_PASSWORD    — App-specific password from appleid.apple.com
# APPLE_TEAM_ID                  — 10-char team ID from developer.apple.com/account
# GITHUB_TOKEN                   — Provided automatically by Actions

jobs:
  build-dmg:
    name: Build & Notarize DMG
    runs-on: macos-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-node@v4
        with:
          node-version: '22'
          cache: 'npm'
      - run: npm ci
      - name: Import Developer ID certificate
        uses: apple-actions/import-codesign-certs@v3
        with:
          p12-file-base64: ${{ secrets.DEVELOPER_ID_CERT_BASE64 }}
          p12-password: ${{ secrets.DEVELOPER_ID_CERT_PASSWORD }}
      - name: Build, sign, notarize & publish DMG
        env:
          APPLE_ID: ${{ secrets.APPLE_ID }}
          APPLE_APP_SPECIFIC_PASSWORD: ${{ secrets.APPLE_APP_SPECIFIC_PASSWORD }}
          APPLE_TEAM_ID: ${{ secrets.APPLE_TEAM_ID }}
          GH_TOKEN: ${{ secrets.GITHUB_TOKEN }}
        run: npm run electron:build:dmg -- --publish always

  build-mas:
    name: Build MAS Package
    runs-on: macos-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-node@v4
        with:
          node-version: '22'
          cache: 'npm'
      - run: npm ci
      - name: Import MAS Application certificate
        uses: apple-actions/import-codesign-certs@v3
        with:
          p12-file-base64: ${{ secrets.MAS_CERT_BASE64 }}
          p12-password: ${{ secrets.MAS_CERT_PASSWORD }}
      - name: Import MAS Installer certificate
        uses: apple-actions/import-codesign-certs@v3
        with:
          p12-file-base64: ${{ secrets.MAS_INSTALLER_CERT_BASE64 }}
          p12-password: ${{ secrets.MAS_INSTALLER_CERT_PASSWORD }}
      - name: Build MAS pkg
        env:
          APPLE_TEAM_ID: ${{ secrets.APPLE_TEAM_ID }}
        run: npm run electron:build:mas
      - name: Upload MAS pkg artifact
        uses: actions/upload-artifact@v4
        with:
          name: jobhunt-mas-${{ github.ref_name }}
          path: dist/*.pkg
          retention-days: 30
```

### Notarization hook

Create `scripts/notarize.cjs` (must be CommonJS — electron-builder's `afterSign` hook uses `require()`):

```js
const { notarize } = require('@electron/notarize');

exports.default = async function notarizing(context) {
  if (context.electronPlatformName !== 'darwin') return;
  // Skip notarization in local dev builds (APPLE_ID not set)
  if (!process.env.APPLE_ID) return;

  await notarize({
    tool: 'notarytool',
    appPath: `${context.appOutDir}/${context.packager.appInfo.productFilename}.app`,
    appleId: process.env.APPLE_ID,
    appleIdPassword: process.env.APPLE_APP_SPECIFIC_PASSWORD,
    teamId: process.env.APPLE_TEAM_ID,
  });
};
```

Install: `npm install --save-dev @electron/notarize`

The `afterSign` hook is wired in `package.json` build config (task-029 adds `"afterSign": "scripts/notarize.cjs"`).

### First MAS submission

The MAS job uploads a `.pkg` artifact (30-day retention). First App Store submission: download artifact, submit manually via Transporter.app (free, from the Mac App Store). Subsequent versions can automate submission via `xcrun altool` if desired.

## Dependency

Depends on task-029 (electron-builder dual-target config), which defines the `electron:build:dmg` and `electron:build:mas` scripts and the `afterSign` hook reference.

## Verification

- `.github/workflows/release.yml` is valid YAML (`actionlint` passes)
- `scripts/notarize.cjs` exists and exits cleanly when `APPLE_ID` is absent
- `@electron/notarize` is in `devDependencies`
- All 9 required secrets are documented in the workflow file comments
- `npm test` passes
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 .github/workflows/release.yml exists and passes actionlint
- [x] #2 Workflow triggers on push to tags matching v*
- [x] #3 build-dmg job: imports Developer ID cert, builds with --publish always, notarizes
- [x] #4 build-mas job: imports MAS Application + Installer certs, builds pkg, uploads artifact with 30-day retention
- [x] #5 scripts/notarize.cjs uses notarytool and skips gracefully when APPLE_ID env var is absent
- [x] #6 @electron/notarize is in devDependencies
- [x] #7 All 9 required secrets are documented in workflow file comments
- [x] #8 npm test passes
<!-- AC:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Created .github/workflows/release.yml with build-dmg (Developer ID sign + notarize + publish to GitHub Releases) and build-mas (MAS Application + Installer certs, pkg artifact with 30-day retention) jobs, both triggered on v* tags. All 9 required secrets documented in comments. Created scripts/notarize.cjs using notarytool, skips gracefully when APPLE_ID absent. Added @electron/notarize ^3.1.1 to devDependencies. 459 tests pass.
<!-- SECTION:FINAL_SUMMARY:END -->
