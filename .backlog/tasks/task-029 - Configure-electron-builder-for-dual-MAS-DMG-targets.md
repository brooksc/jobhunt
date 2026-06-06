---
id: TASK-029
title: Configure electron-builder for dual MAS + DMG targets
status: Done
assignee: []
created_date: '2026-06-06 22:41'
updated_date: '2026-06-06 23:07'
labels:
  - electron
  - mas
  - build
milestone: m-0
dependencies:
  - TASK-027
modified_files:
  - package.json
priority: high
ordinal: 3000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
## Problem

The current `electron-builder` config in `package.json` only targets a DMG with signing disabled (`identity: null`, `sign: false`). It needs to support two separate build targets:

1. **GitHub DMG** — signed with Developer ID Application certificate, notarized, distributed via GitHub Releases
2. **Mac App Store (MAS)** — signed with Mac App Store Application + Installer certificates, packaged as `.pkg`, submitted to App Store Connect

These targets have different signing identities, different entitlements (task-027), and different `hardenedRuntime` settings. The `jobhunt://` URL scheme must also be declared in `Info.plist` for MAS, which electron-builder handles via the `protocols` field.

## Implementation

### `package.json` — replace the `build` section

```json
"build": {
  "appId": "com.jobhunt-app.jobhunt",
  "productName": "Jobhunt",
  "directories": { "output": "dist" },
  "files": ["electron/**/*", "server/**/*", "static/**/*", "package.json"],
  "icon": "build/icons/icon",
  "afterSign": "scripts/notarize.cjs",
  "protocols": [
    { "name": "Jobhunt", "schemes": ["jobhunt"] }
  ],
  "mac": {
    "category": "public.app-category.productivity",
    "icon": "build/icons/icon.icns",
    "hardenedRuntime": true,
    "entitlements": "build/entitlements.dmg.plist",
    "entitlementsInherit": "build/entitlements.dmg.plist",
    "target": [
      { "target": "dmg", "arch": ["arm64", "x64"] }
    ]
  },
  "mas": {
    "entitlements": "build/entitlements.mas.plist",
    "entitlementsInherit": "build/entitlements.mas.inherit.plist",
    "hardenedRuntime": false,
    "target": [
      { "target": "mas", "arch": ["arm64", "x64"] }
    ]
  },
  "dmg": {
    "sign": false
  }
}
```

NOTE: `identity` is NOT hardcoded — it is injected at build time via `CSC_LINK`/`CSC_KEY_PASSWORD` env vars. This keeps certs out of source control.

### `package.json` — build scripts

```json
"electron:build": "electron-builder --dir",
"electron:build:dmg": "electron-builder --mac dmg",
"electron:build:mas": "electron-builder --mac mas",
"electron:dist": "electron-builder --mac dmg mas"
```

`electron:build` (unpacked, unsigned) is kept for local dev/testing.

### URL scheme

The `protocols` field causes electron-builder to inject `CFBundleURLTypes` into `Info.plist` for both targets. The existing `app.setAsDefaultProtocolClient('jobhunt')` call in `main.js` can remain — it handles dev-mode registration and the `process.defaultApp` argv case. Both coexist without conflict.

### Remove legacy fields

Remove `"identity": null` and `"sign": false` from the top-level `dmg` config block (signing is now per-target via env vars).

## Dependency

Requires task-027 (entitlement plist files) to be merged first so `build/entitlements.*.plist` exist.

## Verification

- `npm run electron:build` completes successfully (unpacked, unsigned)
- `npm run electron:build:dmg` produces a `.dmg` in `dist/` (signing may fail locally without cert — that's expected; verify build config is structurally correct)
- `npm run electron:build:mas` produces a `.pkg` in `dist/` (or fails at signing step)
- `dist/mac-arm64/Jobhunt.app/Contents/Info.plist` contains `CFBundleURLTypes` with `jobhunt` scheme
- `npm test` passes
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 package.json build section has separate mac and mas config blocks with correct entitlement file references
- [x] #2 protocols field declares jobhunt:// scheme — verified in built Info.plist CFBundleURLTypes
- [x] #3 npm run electron:build (unpacked/unsigned) succeeds
- [x] #4 npm run electron:build:dmg produces a dmg artifact
- [x] #5 npm run electron:build:mas produces a mas/pkg artifact
- [x] #6 identity field is NOT hardcoded in package.json
- [x] #7 Legacy identity:null and sign:false fields are removed from dmg block
- [x] #8 npm test passes
<!-- AC:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Added protocols field (jobhunt:// scheme → CFBundleURLTypes in Info.plist), afterSign hook reference, electron:build:dmg and electron:build:mas scripts, and electron:dist. Removed legacy dmg.sign:false block. identity not hardcoded. 459 tests pass.
<!-- SECTION:FINAL_SUMMARY:END -->
