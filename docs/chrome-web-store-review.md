# Chrome Web Store Review Notes

Use these notes when submitting the Jobhunt Capture extension for review.

## Single Purpose

Jobhunt Capture captures job posting page text and structured data, then sends it to the local Jobhunt Mac app so the user can store, organize, and extract fields from job postings locally.

The local companion app is required because Jobhunt stores captures locally in the native macOS app and runs local-first workflows from the desktop app.

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
11. Verify the extension opens the capture queue and says the capture is saved locally.
12. Use Export CSV and verify Chrome downloads a CSV containing the saved capture.
13. Reopen the Mac app.
14. Use Sync to Jobhunt from the capture queue and verify the queued capture is written to the app.

## Privacy Policy

Privacy policy URL: **https://jobhunt-app.com/privacy**

## Required Disclosure

The store listing should state:

- The extension sends captured job posting content only to the local Jobhunt companion app at `127.0.0.1`.
- The companion app is required for storage, review workflows, extraction, and scoring.
- Captures can be queued in Chrome extension storage when the companion app is not running.
- Queued captures can be exported as CSV for use in Google Sheets or another tracker.
- Optional LLM extraction depends on the provider configured inside the Mac app.
- For Greenhouse-hosted job boards only, the extension makes a direct request to Greenhouse's
  public job API (`boards-api.greenhouse.io`) to enrich the posting, sending only a board
  identifier and job ID from the page URL — no credentials or personal data. This is the only
  external (non-localhost) server the extension contacts.

## Before each submission

- [ ] Verify `chromestore/store-listing.md` privacy copy and `chromestore/PRIVACY.md` agree and do
      not make an unscoped "no data leaves your device" claim (the Greenhouse public-API enrichment
      is an exception that must be disclosed in both).

## Local Server Details

The extension service worker communicates with the companion app on these loopback ports:

- `http://127.0.0.1:8765`
- `http://127.0.0.1:8766`
- `http://127.0.0.1:8767`
- `http://127.0.0.1:8768`
- `http://127.0.0.1:8769`

The extension does not send local HTTP requests from the page context. Page scripts collect the selected page content and return it to the service worker; the service worker posts to the local app.

The local app handles Chrome extension preflight requests on write endpoints and includes `Access-Control-Allow-Private-Network: true` when Chrome requests private-network access. It does not grant broad website origins access to the write endpoints.
