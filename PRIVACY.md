---
layout: default
title: Privacy Policy
---

# Privacy Policy — Jobhunt

**Last updated: June 2026**

## Overview

Jobhunt is a local-first application. It does not collect, transmit, or store any personal data on remote servers. Everything stays on your machine.

## What the app collects

Jobhunt stores data you explicitly provide: job posting content captured via the Chrome extension, your resume text (pasted during onboarding), and your location preferences and settings. All of this is stored in a local SQLite database on your Mac under `~/.config/jobhunt/`.

## What the Chrome extension collects

When you click the toolbar button, the extension reads the current tab's URL, page title, visible text, and any structured data (JSON-LD) on the page. This content is sent only to the Jobhunt app running locally on your machine via `http://127.0.0.1`. Nothing is sent to any external server.

If the local app is not running, captures are held temporarily in Chrome's local extension storage (`chrome.storage.local`) on your device until you sync or clear them.

## AI processing

Jobhunt sends job description text to an AI model for extraction and fit scoring. By default this is a local model via LM Studio or Ollama — no data leaves your machine. If you configure a cloud provider (OpenAI, Anthropic, Google, OpenRouter), job description text is sent to that provider under their own privacy policy. Your resume is included in fit-scoring prompts.

## Data sharing

We do not sell, share, or transfer any user data to third parties for any purpose. The app has no analytics, no telemetry, and no crash reporting.

## Data retention

All data is stored locally on your device. You can delete it at any time by removing the database file or uninstalling the app.

## Contact

Questions? Open an issue at [github.com/brooksc/jobhunt/issues](https://github.com/brooksc/jobhunt/issues) or visit [jobhunt-app.com](https://jobhunt-app.com).
