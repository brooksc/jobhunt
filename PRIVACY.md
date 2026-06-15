---
layout: default
title: Privacy Policy
---

# Privacy Policy — Jobhunt

**Last updated: June 2026**

## Overview

Jobhunt is a local-first application. By default, all job data stays on your machine. When you choose to configure a cloud or remote AI provider, job description and resume text is sent to that provider to perform AI processing — no data passes through Jobhunt's servers at any point.

## What the app stores

Jobhunt stores data you explicitly provide: job posting content captured via the Chrome extension, your resume text, and your settings. All data is held in a local SwiftData database on your Mac.

**Storage paths:**

| Distribution | Path |
|---|---|
| DMG (direct download) | `~/Library/Application Support/Jobhunt/jobhunt.store` |
| MAS (Mac App Store, sandboxed) | `~/Library/Containers/com.jobhunt-app.jobhunt/Data/Library/Application Support/Jobhunt/jobhunt.store` |

You can delete the database at any time to remove all stored data.

## What the Chrome extension collects

When you click the toolbar button, the extension reads the current tab's URL, page title, visible text, and any structured data (JSON-LD) on the page. This content is sent only to the Jobhunt app running locally on your machine via `http://127.0.0.1`. The app's local HTTP server binds to the loopback interface only, so it is not reachable from other devices on your network. It also only accepts requests from the approved Jobhunt browser extension.

**Greenhouse job board API:** When capturing a job from a Greenhouse-hosted job board (e.g. `boards.greenhouse.io`), the extension makes a direct request to the Greenhouse public API (`https://boards-api.greenhouse.io/v1/boards/…/jobs/…`) to retrieve structured job data. This request goes from your browser to Greenhouse's servers and is subject to Greenhouse's privacy policy. No credentials or personal data are included in this request; it is equivalent to loading a public webpage. No other external server is contacted by the extension.

**Offline queue:** If the local app is not running, captures are held temporarily in Chrome's local extension storage (`chrome.storage.local`) on your device. Queued items may contain the full URL, page title, selected text, and visible text of each captured page. Queued captures are automatically purged after **7 days** or when the queue exceeds **50 items** (oldest removed first). You can clear all queued captures at any time from the extension status page (click the Jobhunt toolbar icon, then open the queue view).

## AI processing

Jobhunt is local-first: by default, AI extraction and fit scoring use a local model via LM Studio or Apple Foundation Models — no data leaves your machine.

If you configure a cloud or remote AI provider, job description text and resume text are sent from your device **directly to that provider** under their privacy policy. Jobhunt never receives this data.

Supported providers:

| Provider | Data destination |
|---|---|
| LM Studio (default) | Local only — `127.0.0.1` |
| Apple Foundation Models | Local only — on-device |
| Custom endpoint on `127.0.0.1` / `localhost` / `::1` | Local only |
| OpenAI, Anthropic, Google, OpenRouter | Provider's servers (requires your explicit consent) |
| Custom remote OpenAI-compatible endpoint (non-loopback) | User-configured server (requires your explicit consent) |

Consent is required before any data is sent to a cloud or non-local custom endpoint. You can revoke consent in **Settings → AI Provider** at any time.

## Data sharing

We do not sell, share, or transfer any user data to third parties for any purpose. The app has no analytics, no telemetry, and no crash reporting.

## Data retention

All job data is stored locally on your device. Capture text held in the Chrome extension's offline queue is retained for up to 7 days or 50 items, whichever limit is hit first.

## Contact

Questions? Open an issue at [github.com/brooksc/jobhunt/issues](https://github.com/brooksc/jobhunt/issues) or visit [jobhunt-app.com](https://jobhunt-app.com).
