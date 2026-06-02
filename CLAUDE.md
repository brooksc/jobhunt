# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What it is

Local-first job tracking tool. A browser extension captures job postings; a local Node.js server stores them in SQLite and runs LLM extraction (via LM Studio); a React SPA served from the same process provides the UI.

## Running

```bash
npm run dev          # hot-reload server (node --watch)
npm start            # supervised local server; killing the node child restarts it
npm run serve:once   # one-shot server without restart supervision
node server/index.js serve --port 8765 --auto-extract
node server/mcp.js --db-path ~/.config/jobhunt/jobhunt.db
```

Default: `http://127.0.0.1:8765`. DB lives at `~/.config/jobhunt/jobhunt.db` (override with `--db-path` or `JOBHUNT_DB_PATH`).

When changing server code during an interactive session, restart the app by killing the `node server/index.js serve` child process; `npm start` runs a supervisor loop that should automatically bring it back.

CLI subcommands: `init`, `extract`, `jobs list`, `jobs status`, `jobs note`, `duplicates list`, `export csv`.

## Architecture

**Server** (`server/`) — ES modules, Node 26+ required (uses `node:sqlite` built-in):
- `index.js` — CLI entry point (commander), wires together all subcommands
- `api.js` — Express app, ~38 REST endpoints, serves `static/` as the frontend
- `db.js` — all SQLite access (synchronous `DatabaseSync`); schema defined inline as `SCHEMA` const
- `extract.js` — LLM extraction and fit-scoring via OpenAI-compatible API (targets LM Studio at `http://127.0.0.1:1234`)
- `cleaning.js` — text normalization before hashing/storage
- `availability.js` — checks whether captured job URLs are still live
- `export.js` — CSV export

**Frontend** (`static/`) — no build step; React + Babel loaded from `static/vendor/` at runtime, JSX served directly:
- `index.html` — loads vendor scripts then all JSX files as `type="text/babel"`; the server injects cache-busting version hashes
- `app.jsx` — top-level `JobhuntApp` component; hash-based routing (`#/jobs`, `#/sites`, etc.)
- `shell.jsx` — nav shell and data-loading layer; polls `/api/ui-data`
- `components.jsx` — shared UI primitives
- `screens/` — one file per route: `jobs.jsx`, `detail.jsx`, `sites.jsx`, `duplicates.jsx`, `needs.jsx`, `settings.jsx`, `llm_queue.jsx`, `dashboard.jsx`

**Chrome extension** (`extension/`) — Manifest V3 extension with a service worker (`service_worker.js`), capture script (`capture.js`), and note UI (`note.html/js`). POSTs captured page content to the local server. Install via `chrome://extensions` → Load unpacked → select `extension/`.

**Data flow**: browser extension POSTs to `/captures` → DB stores raw HTML/text → LLM queue processes it → extracted JSON written back to `jobs` table → `/api/ui-data` returns everything to the SPA in one payload.

**LLM integration**: `extract.js` talks to any OpenAI-compatible endpoint. It tries structured JSON output first, falls back to `json_object` format, then plain text with `jsonrepair`. Settings (`llm_base_url`, `llm_model`, `resume_text`, etc.) are stored in a `settings` key-value table.

## Key conventions

- Every `server/*.js` file has a comment `// Mirrors python/src/jobhunt/*.py` — there was a prior Python implementation; the JS is the current one.
- `db.js` exports functions that accept an optional `dbPath` and call `initDb(dbPath)` internally — this means DB connections are opened per-call (synchronous, fine for SQLite).
- The `jobs` table has both `status` (user-facing: saved/applied/interview/offer/rejected/archived) and `extraction_status` (pipeline state: pending/running/succeeded/failed).
- Legacy status values (`interested`, `interviewing`, `closed`, `ignored`) are normalized on read via `LEGACY_STATUS_MAP`.
- `server/mcp.js` exposes the Jobhunt MCP stdio server for Claude Code/Codex. The old Python `jobhunt-mcp` entry point is not present in this repo.
- `SETTINGS_DEFAULTS` in `db.js` defines the whitelist of valid setting keys; `PATCH /api/settings` ignores unknown keys.
