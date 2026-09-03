---
id: TASK-655
title: >-
  MCP setup is undiscoverable in the DMG — register it from the app or explain
  how
status: To Do
assignee: []
created_date: '2026-08-01 20:15'
labels:
  - mcp
  - onboarding
  - ui
dependencies: []
priority: medium
ordinal: 90000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
A user who installs the DMG from GitHub gets the MCP helper but no way to learn it exists.

**What ships today**
- `Project.swift` copies `jobhunt-mcp` into `/Applications/Jobhunt.app/Contents/Helpers/jobhunt-mcp` for DMG builds (post-action, skipped for `*MAS*`), signed with hardened runtime and notarized with the app.
- The MCP token (`~/.jobhunt-mcp-token`) generates itself, so once a client is registered it works — provided the app is running.
- **Nothing registers the helper with any client.** No writes to `~/.claude.json`, `~/Library/Application Support/Claude/claude_desktop_config.json`, `~/.codex/config.toml`, or `~/.gemini/settings.json`.

**Discoverability today**
- `README.md:52` ("MCP integration (DMG only)") has copy-paste snippets for Claude Code, Claude Desktop, Codex CLI and Gemini CLI. That's the only documentation.
- Nothing in the app mentions MCP. The sole hit under `app/` is a Debug-tab health row labelled "MCP token" (`DebugTab.swift:77`) — a green/red dot that never says what it's for.
- So anyone who downloads the DMG from Releases and doesn't read the README never learns the integration exists.

**Design is open** — decide later. Sketch of the tradeoff:
- *Silent auto-registration on first launch*: rejected as the default. Writing into another app's config without being asked is invasive, can clobber hand-edited JSON/TOML, and silently no-ops for clients that aren't installed yet. Any write must be user-initiated.
- *In-app setup panel* (preferred starting point): helper path with a copy button, the four client snippets, and per-client "Register" buttons that shell out (`claude mcp add jobhunt -- <path>`, `codex mcp add …`) only on click.

**Must be stated wherever this lands** (both are buried in the README):
1. The app has to be running for the bridge to work.
2. MAS builds have no helper (sandbox) — show that instead of a path that doesn't exist.

**Placement idea:** `SettingsView` has General/Jobs/AI/Data/Debug. MCP isn't an AI-provider concern; a new **Integrations** tab could host it alongside browser-extension status — the app's two external connections, neither of which has a home today.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 A DMG user can discover the MCP integration without reading the GitHub README
- [ ] #2 Any write to a third-party client config is user-initiated, never automatic on launch
- [ ] #3 Registration does not clobber existing hand-edited entries in the target config
- [ ] #4 The helper path is shown and copyable for manual setup, covering Claude Code, Claude Desktop, Codex CLI and Gemini CLI
- [ ] #5 The app-must-be-running precondition is stated in the UI
- [ ] #6 A MAS build explains the helper is unavailable rather than showing a path that does not exist
<!-- AC:END -->
