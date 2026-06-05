# Jobhunt

**[jobhunt-app.com](https://jobhunt-app.com)** · [Issues](https://github.com/brooksc/jobhunt/issues)

Local-first job tracking. A Chrome extension captures job postings from any site; a Mac app stores them in SQLite, runs AI extraction via LM Studio, and shows a full tracking UI — all on your own machine, no cloud required.

![Jobs view](marketing/screenshots/jobs-detail.png)

## Installation

### Mac App

1. Download `Jobhunt-0.2.0.dmg` from the [latest release](https://github.com/brooksc/jobhunt/releases/latest).
2. Open the DMG and drag **Jobhunt** to Applications.
3. First launch: right-click the app → **Open** to bypass Gatekeeper.

> **The app is not yet signed by Apple.** macOS may show a "damaged" or "cannot be opened" error. If that happens, run this once in Terminal:
> ```bash
> xattr -cr /Applications/Jobhunt.app
> ```
> Then launch normally.

### Chrome Extension

Install from the [Chrome Web Store](https://chromewebstore.google.com/detail/jobhunt-capture/hfidoakacpbhopmcpikckjhibfnobjjb) or load it unpacked:

1. Open `chrome://extensions`.
2. Enable **Developer mode**.
3. Click **Load unpacked** and select the `extension/` directory from this repo.

## Requirements

- **LM Studio** — provides the local LLM for AI extraction and resume-fit scoring. Start LM Studio's local server on `http://127.0.0.1:1234` and load a model (Gemma 3, Qwen 3, or similar instruction-tuned model recommended).

## Getting Started

1. Launch the Jobhunt Mac app.
2. On first run, the onboarding wizard walks you through: setting your job preferences, connecting to LM Studio, and pasting your resume for fit scoring.
3. Browse to any job posting and click the Jobhunt extension icon to capture it.
4. The app extracts structured fields (title, company, location, salary, requirements) and scores your fit against your resume automatically.

## Features

- **Capture from anywhere** — works on LinkedIn, Greenhouse, Lever, Ashby, iCIMS, Workday, and most job boards
- **AI extraction** — pulls salary, requirements, work mode, and more from unstructured job descriptions
- **Resume fit scoring** — ranks each job against your resume with dimension-level explanations
- **Duplicate detection** — groups identical or near-identical postings across different sources
- **Dashboard** — daily activity view showing pipeline progress over time
- **Offline queue** — captures are queued in the extension if the Mac app isn't running
- **Export** — download CSV from the UI or via `node server/index.js export csv`
- **MCP server** — expose your job database as an MCP tool for Claude and other AI assistants

---

## Developer Guide

### Stack

- **Server**: Node.js 26, Express, `node:sqlite` (no external ORM)
- **Frontend**: React (runtime Babel, no build step), served from the Node server
- **Extension**: Chrome Manifest V3, service worker with offline retry queue
- **Desktop**: Electron 42, electron-builder for DMG packaging
- **AI**: OpenAI-compatible chat completions via LM Studio (or any compatible endpoint)

### Setup

Requires Node.js 26 or newer.

```bash
npm install
```

### Run (development)

```bash
npm start          # supervised server loop — restarts on crash
npm run serve:once # one-shot server
```

The UI is at `http://127.0.0.1:8765`.

### Runtime Data

```
~/.config/jobhunt/jobhunt.db             # SQLite database
~/.config/jobhunt/jobhunt-llm-debug.log  # LLM request/response log
```

Override with env vars:

```bash
JOBHUNT_CONFIG_DIR=/path/to/config npm start
JOBHUNT_DB_PATH=/path/to/jobhunt.db npm start
```

### Build

```bash
./scripts/rebuild-and-launch.sh          # build + launch (auto-bumps patch version)
./scripts/build-electron.sh              # unpacked build only
./scripts/build-electron.sh --dist       # build distributable DMG
./scripts/package-extension.sh           # zip extension for Chrome Web Store
./scripts/release.sh                     # bump minor, commit, tag, build both artifacts
```

### Versioning

`x.y.z` — patch auto-increments on dev builds, minor on releases, major for milestones.

```bash
./scripts/bump-version.sh patch   # z++
./scripts/bump-version.sh minor   # y++, z=0
./scripts/bump-version.sh major   # x++, y=0, z=0
```

### Verify

```bash
npm test
npm run lint
npm run typecheck
npm run eval:llm   # live LLM extraction quality check (requires LM Studio running)
```

### Queue AI Processing

```bash
node server/index.js jobs queue-ai 19,74,#90 --mode extract --process
```

Modes: `extract`, `fit_score`, `missing_fields`.

### MCP Server

```bash
node server/mcp.js  # exposes job DB tools for Claude Desktop and compatible clients
```

Add to `claude_desktop_config.json`:

```json
{
  "mcpServers": {
    "jobhunt": {
      "command": "node",
      "args": ["/path/to/jobhunt/server/mcp.js"]
    }
  }
}
```
