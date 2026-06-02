# Chrome Web Store Review Notes

Use these notes when submitting the Jobhunt Capture extension for review.

## Single Purpose

Jobhunt Capture captures job posting page text and structured data, then sends it to the local Jobhunt Mac app so the user can store, organize, and extract fields from job postings locally.

The local companion app is required because Jobhunt stores captures in a local SQLite database and runs local-first workflows from the desktop app.

## Reviewer Test Instructions

Provide reviewers with a built macOS app artifact or a download link before submission.

1. Install and launch the Jobhunt Mac app.
2. Confirm the app opens the local Jobhunt UI.
3. Install the extension from the submitted package.
4. Open a public job posting page in Chrome.
5. Click the Jobhunt Capture extension button.
6. Confirm the capture preflight dialog.
7. Verify the extension shows an OK badge.
8. Return to the Jobhunt Mac app and verify the captured posting appears in the job list.
9. Close the Mac app.
10. Capture another job posting.
11. Verify the extension opens the capture status page and says the capture is queued.
12. Reopen the Mac app and capture another posting to flush the queued capture.

## Required Disclosure

The store listing should state:

- The extension sends captured job posting content only to the local Jobhunt companion app at `127.0.0.1`.
- The companion app is required for storage, review workflows, extraction, and scoring.
- Captures can be queued in Chrome extension storage when the companion app is not running.
- Optional LLM extraction depends on the provider configured inside the Mac app.

## Local Server Details

The extension service worker communicates with the companion app on these loopback ports:

- `http://127.0.0.1:8765`
- `http://127.0.0.1:8766`
- `http://127.0.0.1:8767`
- `http://127.0.0.1:8768`
- `http://127.0.0.1:8769`

The extension does not send local HTTP requests from the page context. Page scripts collect the selected page content and return it to the service worker; the service worker posts to the local app.

The local app handles Chrome extension preflight requests on write endpoints and includes `Access-Control-Allow-Private-Network: true` when Chrome requests private-network access. It does not grant broad website origins access to the write endpoints.
