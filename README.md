# Jobhunt

Local-first job tracking for captured job descriptions. A Chrome extension sends job pages to a local Node service, SQLite stores the data, LM Studio extracts structured fields, and the bundled React UI runs at `http://127.0.0.1:8765`.

## Requirements

- Node.js 26 or newer. The server uses Node's built-in `node:sqlite` module.
- npm.
- Chrome or Chromium for the unpacked extension.
- LM Studio for AI extraction and resume-fit scoring.

Install dependencies:

```bash
npm install
```

## Run

Use the supervised local server during normal development:

```bash
npm start
```

`npm start` runs `scripts/run-server-loop.sh`. It runs the verification commands, starts `node server/index.js serve`, and restarts the child server if it exits. If server code changes while this loop is running, kill the `node server/index.js serve` child process and the loop will bring it back.

Other useful commands:

```bash
npm run serve:once       # one-shot server without restart supervision
node server/index.js serve --port 8765 --auto-extract
curl http://127.0.0.1:8765/health
```

The UI is served from `http://127.0.0.1:8765`.

## Runtime Data

Runtime files live under `~/.config/jobhunt` by default:

- Database: `~/.config/jobhunt/jobhunt.db`
- LLM debug log: `~/.config/jobhunt/jobhunt-llm-debug.log`

Overrides:

```bash
JOBHUNT_CONFIG_DIR=/path/to/config npm start
JOBHUNT_DB_PATH=/path/to/jobhunt.db npm start
JOBHUNT_LLM_DEBUG_LOG_PATH=/path/to/debug.log npm start
```

The app still migrates old `.data/` files into the config directory when no explicit DB path is set.

## Chrome Extension

1. Open `chrome://extensions`.
2. Enable Developer mode.
3. Click Load unpacked.
4. Select this repo's `extension/` directory.
5. Start the local server and capture a job page with the extension button.

The extension posts captures to `/captures`. If the local service is unavailable, the service worker keeps a retry queue and reports extension status in the UI sidebar.

The extension can discover the app on `127.0.0.1` ports `8765` through `8769`. When the Mac app is not running, the extension can still read the current page after the preflight confirmation and queue the capture in Chrome local extension storage. Writing to SQLite, marking sites reviewed, extraction, fit scoring, availability checks, and the Jobhunt UI all require the Mac app.

Chrome Web Store submission notes live in `docs/chrome-web-store-review.md`.

## Queue AI Processing

Queue extraction or fit scoring for visible job numbers:

```bash
node server/index.js jobs queue-ai 19,74,#90 --mode extract --process
```

Modes are `extract`, `fit_score`, and `missing_fields`. Without `--process`, the command only enqueues the work.

The same operation is available over HTTP:

```bash
curl http://127.0.0.1:8765/api/jobs/bulk/llm-by-number \
  -H "Content-Type: application/json" \
  -d '{"job_numbers":[19,74,90],"mode":"extract"}'
```

## LM Studio

Start LM Studio's local server on `http://127.0.0.1:1234` and load the model configured in Settings. The app uses OpenAI-compatible chat completions and requests structured output with:

```json
{
  "response_format": {
    "type": "json_schema",
    "json_schema": {
      "strict": true
    }
  }
}
```

If structured output fails, the server records durable LLM attempt history in SQLite. Failed attempts are also appended to the debug log when debug logging is enabled in Settings.

### Model evaluation

Use the live LLM evaluation when deciding whether the loaded model is strong enough for Jobhunt's extraction and fit-scoring tasks:

```bash
npm run eval:llm
```

The evaluation uses the same LM Studio structured-output path as the app. It checks known-answer job postings for fields such as company, title, location, work mode, salary bands, skills, requirements, benefits, and application URL. It also scores a strong resume and a weak resume against the same test job to verify that the model ranks the strong fit higher and explains missing requirements for the weak fit.

Override the configured model or endpoint with:

```bash
npm run eval:llm -- --model gemma-4-e2b-it-mlx --base-url http://127.0.0.1:1234
```

## Export

Download CSV from the UI or use:

```bash
node server/index.js export csv --output jobs.csv
```

The served endpoint is `/exports/jobs.csv`.

## Verification

Run the standard checks before calling work done:

```bash
npm test
npm run test:ui
npm run lint
npm run typecheck
```

`npm run lint` currently covers server code. The frontend is runtime-loaded JSX through Babel with no build step, so UI regressions are covered by `npm run test:ui`. Pre-commit hooks are intentionally not installed yet; keep the workflow explicit until the frontend build/lint story is settled.
