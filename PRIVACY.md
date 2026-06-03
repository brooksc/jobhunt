# Privacy Policy — Jobhunt Capture

**Last updated: June 2, 2026**

## Overview

Jobhunt Capture is a Chrome extension that saves job posting pages to a locally-running job tracker app on your own machine. It does not collect, transmit, or store any data on remote servers.

## Data collected

When you click the toolbar button or use the right-click menu, the extension reads the following from the current browser tab:

- Page title and URL
- Visible page text and structured data (JSON-LD)
- Any text you have selected
- Any note you choose to type before saving

## How data is used

All captured data is sent exclusively to a companion app running on your own machine via localhost (`http://127.0.0.1`). It is stored in a local database under your control. No data is sent to any external server, third party, or cloud service.

If the local app is not running, captures are held temporarily in Chrome's local extension storage (`chrome.storage.local`) on your device until you sync or clear them.

## Data sharing

We do not sell, share, or transfer any user data to third parties for any purpose.

## Data retention

All data is stored locally on your device. You can delete it at any time by clearing the extension's capture queue or removing the local database.

## Contact

Questions? Open an issue at https://github.com/brooksc/jobhunt
