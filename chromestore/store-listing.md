# Chrome Web Store Listing — Jobhunt Capture

## Metadata

| Field | Value |
|---|---|
| Name | Jobhunt Capture |
| Category | Productivity |
| Language | English |
| Visibility | Unlisted |
| Version | 1.0.1 |

---

## Short description (132 char max)

```
Save job postings from any page to your local Jobhunt tracker. Captures queue offline and sync when the app is running.
```
*(119 chars)*

---

## Long description

```
Jobhunt Capture saves job postings from any web page to your local Jobhunt job tracker with one click.

HOW IT WORKS
Click the toolbar button on any job posting page. A preflight check confirms the page contains key details (title, location, salary, remote status) before you save. The captured content is sent to your local Jobhunt app for LLM extraction, fit scoring, and tracking.

WORKS OFFLINE TOO
If the Jobhunt app isn't running, captures are stored locally in the extension queue and synced automatically the next time you capture a job while the app is reachable — or on demand via the Capture queue page (right-click the toolbar icon → Open capture queue → Sync to Jobhunt).

FEATURES
• One-click capture from any job posting page
• Preflight dialog confirms what data was detected before saving
• Save with a personal note (right-click → Save job with note)
• Mark a site as reviewed (right-click → Mark site reviewed)
• Offline capture queue with CSV export for Google Sheets or other trackers
• Duplicate detection — won't queue the same URL twice

REQUIRES THE JOBHUNT MAC APP
This extension is a companion to the Jobhunt Mac app, which runs locally on your machine and handles LLM extraction, fit scoring, availability checking, and the full job tracking UI. The extension connects to the app over localhost.

Learn more and download at jobhunt-app.com
```

---

## Permissions justifications

These are entered in the "Permissions" step of the submission form.

| Permission | Justification |
|---|---|
| `activeTab` | Read the current page's content when the user clicks the toolbar button to capture a job posting. |
| `scripting` | Inject the capture script into the active tab to extract page text, structured data, and metadata. |
| `storage` | Store the offline capture queue locally so jobs captured while the Mac app is offline are not lost. |
| `contextMenus` | Add right-click menu items: Save job with note, Mark site reviewed, Open capture queue. |
| `downloads` | Export the offline capture queue as a CSV file the user can open in Google Sheets or another tracker. |
| Host: `http://127.0.0.1:876[5-9]/*` | Send captured job data to the Jobhunt Mac app running on localhost. Multiple ports are probed to find the active instance. |

---

## Privacy policy

Privacy policy URL: **https://jobhunt-app.com/privacy**

Suggested copy:

> Jobhunt Capture does not collect or store any personal data on remote servers, and it has no analytics or tracking. Captured page content is sent only to a locally-running companion app on your own machine (localhost) and stored in a local database under your control.
>
> One exception: when you capture a job from a Greenhouse-hosted job board (e.g. `boards.greenhouse.io`), the extension makes a direct request to Greenhouse's public job API to enrich the posting. That request includes only a board identifier and job ID taken from the page URL — never credentials, account information, or personal data. No other external servers are contacted. See the full privacy policy for details.

---

## Assets

| Asset | File | Status |
|---|---|---|
| Store icon (128×128) | `icon-128.png` | ✓ ready |
| Screenshot 1 (1280×800) | `screenshot-capture-queue-1280x800.png` | ✓ ready |
| Small promo tile (440×280) | — | Optional; not needed for unlisted |
| Marquee promo tile (1400×560) | — | Optional; not needed for unlisted |
| Extension zip | `jobhunt-capture-1.0.1.zip` | Built at release from extension/ (matches manifest version) |
