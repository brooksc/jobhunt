# Jobhunt

**[jobhunt-app.com](https://jobhunt-app.com)** · [Issues](https://github.com/brooksc/jobhunt/issues)

Local-first job tracking. A Chrome extension captures job postings from any site; a native macOS app stores them in SwiftData, runs AI extraction, and shows a full tracking UI — all on your own machine, no cloud required.

![Jobs view](marketing/screenshots/jobs-detail.png)

## Overview

Jobhunt is a native macOS app for job hunters. Capture postings from any job board via the Chrome extension, let the AI extract structured fields and score your resume fit, and track your pipeline from application to offer — entirely offline.

**Dual distribution:**
- **DMG** — direct download from GitHub Releases (includes MCP server integration)
- **MAS** — Mac App Store (sandboxed; MCP not available)

## Installation

### Mac App

**From GitHub Releases (recommended):**
1. Download the latest `Jobhunt-*.dmg` from [Releases](https://github.com/brooksc/jobhunt/releases/latest).
2. Open the DMG and drag **Jobhunt** to Applications.

**From Mac App Store:**
- Search for "Jobhunt" on the App Store.

### Chrome Extension

Install from the [Chrome Web Store](https://chromewebstore.google.com/detail/jobhunt-capture/jekcbebhfeidkpapienoflbcaeeknlch) or load unpacked:

1. Open `chrome://extensions`.
2. Enable **Developer mode**.
3. Click **Load unpacked** and select the `extension/` directory.

## Requirements

- **macOS 15.0 (Sequoia)** or later
- **Xcode 16+** (for development)
- **[mise](https://mise.jdx.dev)** — pins the build toolchain via `.mise.toml`: Tuist 4.196.1,
  SwiftLint 0.63.3, SwiftFormat 0.61.1 (the exact versions CI uses)
- **AI Provider**: LM Studio (recommended for local inference), or any OpenAI-compatible endpoint

## Setup (Development)

Install the **pinned** toolchain from `.mise.toml` (same versions as CI — don't install Tuist
separately, or you may generate the project with a different version):

```bash
# Install mise once (https://mise.jdx.dev), then from the repo root:
mise install               # installs the pinned Tuist + SwiftLint + SwiftFormat

# Generate Xcode project
tuist generate --no-open

# Open in Xcode
open Jobhunt.xcodeproj
```

Select the `Jobhunt-DMG` scheme and run.

## Stack

| Layer | Technology |
|---|---|
| Language | Swift 6+ |
| UI | SwiftUI |
| Persistence | SwiftData |
| Networking | Network.framework (HTTP server), URLSession (LLM client) |
| Project | Tuist 4.x |
| Extension | Chrome Manifest V3 (unchanged) |

## Chrome Extension

The extension is unchanged from the original. It captures job postings from any site and queues them for the Mac app. Install from `extension/` (load unpacked) or from the Chrome Web Store.

## AI / LLM

Configure your AI provider in **Settings > AI Provider**. LM Studio running locally on `http://127.0.0.1:1234` is recommended.

Supported providers:
- LM Studio (default, local)
- OpenAI
- Anthropic
- Google
- OpenRouter
- Custom OpenAI-compatible endpoint
- Apple Foundation Models (macOS 26+, DMG only)

## MCP Integration (DMG only)

The DMG build ships a `jobhunt-mcp` helper that bridges stdio JSON-RPC to the running app's HTTP server, exposing your job database as tools for AI assistants.

```bash
claude mcp add jobhunt -- /Applications/Jobhunt.app/Contents/Helpers/jobhunt-mcp
```

**Claude Desktop** — add to `~/Library/Application Support/Claude/claude_desktop_config.json`:

```json
{
  "mcpServers": {
    "jobhunt": {
      "command": "/Applications/Jobhunt.app/Contents/Helpers/jobhunt-mcp"
    }
  }
}
```

The app must be running for MCP to work. MAS users do not get MCP (sandbox restriction).

**MCP trust boundary:** The MCP endpoint is local-only (`127.0.0.1`) and requires a per-device bearer token written to `~/.jobhunt-mcp-token` (owner-readable only). The `job_get` tool omits raw captured page text (`selected_text`, `visible_text`) by default; pass `include_raw_text: true` to include it. Do not expose the MCP port or token to remote systems.

## Distribution

| Channel | Artifact | Signing | Delivery |
|---|---|---|---|
| GitHub Releases | `.dmg` | Developer ID | Attached to GitHub Release |
| Mac App Store | `.pkg` | MAS certificate | Upload via Transporter → App Store Connect |

## Development

### Build

```bash
tuist generate --no-open

# Debug build
xcodebuild build \
  -project Jobhunt.xcodeproj \
  -scheme Jobhunt-DMG \
  -configuration Debug-DMG \
  -destination 'platform=macOS'
```

### Test

**Fast gate** (CoreTests + ServerTests + MCPTests, ~30s) — a *partial* check for quick feedback. The
full CI gate (both-scheme builds, extension tests, SwiftLint/SwiftFormat, coverage) is in
[CONTRIBUTING.md](CONTRIBUTING.md#running-tests); run it before a PR.

```bash
xcodebuild test \
  -scheme Jobhunt-DMG \
  -configuration Debug-DMG \
  -destination 'platform=macOS' \
  -only-testing CoreTests \
  -only-testing ServerTests \
  -only-testing MCPTests \
  CODE_SIGNING_ALLOWED=NO
```

**UI tests** (requires a display; run manually):

```bash
xcodebuild test \
  -project Jobhunt.xcodeproj \
  -scheme Jobhunt-DMG \
  -configuration Debug-DMG \
  -destination 'platform=macOS' \
  -only-testing AppUITests \
  CODE_SIGNING_ALLOWED=NO
```

**LLM eval** (opt-in; requires a running LLM provider):

```bash
# LLMEval lives in the opt-in Jobhunt-Eval scheme (NOT Jobhunt-DMG, which never runs it).
JOBHUNT_LLM_URL=http://127.0.0.1:1234 xcodebuild test \
  -project Jobhunt.xcodeproj \
  -scheme Jobhunt-Eval \
  -destination 'platform=macOS' \
  -only-testing:LLMEval \
  CODE_SIGNING_ALLOWED=NO
```

Add `JOBHUNT_LLM_MIN_ACCURACY=80` to fail when accuracy drops below 80%. See `tests/LLMEval/README.md` for details.

### Versioning

Version is sourced from `Project.swift` `.marketingVersion`. The script updates both
`Project.swift` and `extension/manifest.json`. It does **not** auto-commit.

```bash
./scripts/bump-version.sh patch   # z++   (reads current version from Project.swift)
./scripts/bump-version.sh minor   # y++, z=0
./scripts/bump-version.sh major   # x++, y=0, z=0
./scripts/bump-version.sh 1.2.3  # set explicit version
```

After bumping, commit the changed files manually:
```bash
git add Project.swift extension/manifest.json
git commit -m "chore: bump version to $(grep -o '"[0-9.]*"' Project.swift | head -1 | tr -d '"')"
```

### Runtime Data

```
~/Library/Application Support/Jobhunt/   # SwiftData store
```

## Features

- **Capture from anywhere** — works on LinkedIn, Greenhouse, Lever, Ashby, iCIMS, Workday, and most job boards
- **AI extraction** — pulls salary, requirements, work mode, and more from unstructured job descriptions
- **Resume fit scoring** — ranks each job against your resume with dimension-level explanations
- **Duplicate detection** — groups identical or near-identical postings across sources
- **Dashboard** — daily activity view showing pipeline progress
- **CSV export** — export the job list to CSV via the toolbar or File → Export Job List to CSV… (⌘⇧E). This exports job list fields only and is **not** a full backup. Use **Settings → Back Up Data** to create a complete, restorable backup of your database.
- **Offline queue** — captures are queued in the extension if the app isn't running
- **MCP server** — expose your job database as tools for Claude and other AI assistants (DMG only)
