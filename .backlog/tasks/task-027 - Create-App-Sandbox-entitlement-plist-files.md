---
id: TASK-027
title: Create App Sandbox entitlement plist files
status: To Do
assignee: []
created_date: '2026-06-06 22:38'
labels:
  - signing
  - mas
  - electron
milestone: m-0
dependencies: []
priority: high
ordinal: 2000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
## Problem

The Mac App Store requires all apps to run inside the App Sandbox. Electron apps need three entitlement files:

1. `build/entitlements.mas.plist` — entitlements for the main app binary (MAS build)
2. `build/entitlements.mas.inherit.plist` — entitlements for Electron's child processes (renderer, GPU, network service helpers); these inherit the sandbox but have no additional capabilities
3. `build/entitlements.dmg.plist` — entitlements for the GitHub DMG build (hardened runtime, no sandbox)

These files are referenced by `electron-builder` during code signing. Without them, the MAS build will be rejected by the App Store and the DMG build will fail notarization.

## Implementation

### `build/entitlements.mas.plist`

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <!-- Required: enable the sandbox -->
  <key>com.apple.security.app-sandbox</key>
  <true/>
  <!-- Required: Electron's V8 JIT needs executable memory -->
  <key>com.apple.security.cs.allow-jit</key>
  <true/>
  <!-- Local HTTP server on 127.0.0.1 for Chrome extension communication -->
  <key>com.apple.security.network.server</key>
  <true/>
  <!-- Outbound HTTPS calls to LLM providers (Anthropic, Google, OpenRouter, etc.) -->
  <key>com.apple.security.network.client</key>
  <true/>
</dict>
</plist>
```

### `build/entitlements.mas.inherit.plist`

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>com.apple.security.app-sandbox</key>
  <true/>
  <key>com.apple.security.inherit</key>
  <true/>
</dict>
</plist>
```

### `build/entitlements.dmg.plist`

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <!-- Required for Electron/V8 JIT under Hardened Runtime -->
  <key>com.apple.security.cs.allow-jit</key>
  <true/>
  <!-- Electron loads unsigned native modules -->
  <key>com.apple.security.cs.allow-unsigned-executable-memory</key>
  <true/>
  <!-- Electron loads dylibs not part of the system -->
  <key>com.apple.security.cs.disable-library-validation</key>
  <true/>
</dict>
</plist>
```

### Wire into `package.json` electron-builder config

Update the `build` section of `package.json`:

```json
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
}
```

Note: `identity` and signing credentials are NOT committed here — they are passed via environment variables at build time (`CSC_LINK`, `CSC_KEY_PASSWORD`, `APPLE_TEAM_ID`).

## Verification

- All three plist files exist and are valid XML (run `plutil -lint build/entitlements.*.plist`)
- `electron-builder` config references the correct files per target
- `npm run electron:build` (DMG) completes without signing errors (even with identity:null in dev)
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 build/entitlements.mas.plist exists and is valid XML with app-sandbox, allow-jit, network.server, network.client entitlements
- [ ] #2 build/entitlements.mas.inherit.plist exists with app-sandbox and inherit entitlements
- [ ] #3 build/entitlements.dmg.plist exists with allow-jit, allow-unsigned-executable-memory, disable-library-validation
- [ ] #4 All three files pass `plutil -lint`
- [ ] #5 package.json electron-builder mac section references entitlements.dmg.plist for hardenedRuntime
- [ ] #6 package.json electron-builder mas section references entitlements.mas.plist and entitlements.mas.inherit.plist
<!-- AC:END -->
