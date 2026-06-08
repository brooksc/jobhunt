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

Install from the [Chrome Web Store](https://chromewebstore.google.com/detail/jobhunt-capture/hfidoakacpbhopmcpikckjhibfnobjjb) or load unpacked:

1. Open `chrome://extensions`.
2. Enable **Developer mode**.
3. Click **Load unpacked** and select the `extension/` directory.

## Requirements

- **macOS 15.0 (Sequoia)** or later
- **Xcode 16+** (for development)
- **Tuist 4.196.1** (for project generation)
- **AI Provider**: LM Studio (recommended for local inference), or any OpenAI-compatible endpoint

## Setup (Development)

```bash
# Install Tuist
curl -Ls https://install.tuist.io | bash

# Generate Xcode project
tuist generate

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

## Distribution

| Channel | Artifact | Signing |
|---|---|---|
| GitHub Releases | `.dmg` | Developer ID |
| Mac App Store | `.ipa` | MAS certificate |

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

```bash
xcodebuild test \
  -project Jobhunt.xcodeproj \
  -scheme Jobhunt-DMG \
  -destination 'platform=macOS' \
  -only-testing:CoreTests
```

### Versioning

```bash
./scripts/bump-version.sh patch   # z++
./scripts/bump-version.sh minor   # y++, z=0
./scripts/bump-version.sh major   # x++, y=0, z=0
```

### Runtime Data

```
~/Library/Application Support/Jobhunt/   # SwiftData store
~/Library/Logs/Jobhunt/                  # LLM debug logs
```

## Features

- **Capture from anywhere** — works on LinkedIn, Greenhouse, Lever, Ashby, iCIMS, Workday, and most job boards
- **AI extraction** — pulls salary, requirements, work mode, and more from unstructured job descriptions
- **Resume fit scoring** — ranks each job against your resume with dimension-level explanations
- **Duplicate detection** — groups identical or near-identical postings across sources
- **Dashboard** — daily activity view showing pipeline progress
- **Offline queue** — captures are queued in the extension if the app isn't running
- **MCP server** — expose your job database as tools for Claude and other AI assistants (DMG only)
