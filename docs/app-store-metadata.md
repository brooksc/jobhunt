# App Store Connect — JobHunt listing metadata

> **Live on the Mac App Store:** https://apps.apple.com/us/app/jobhunt-find-your-next-job/id6782679255?mt=12 (App ID `6782679255`)


Copy-paste source for the Mac App Store listing. Field character limits are noted; the values below
are within them. **MAS-specific:** the App Store build is sandboxed and omits the MCP server and
Sparkle self-update (the store handles updates), so the description below intentionally does **not**
mention those — only features the sandboxed build actually ships. The Chrome extension still works
(the MAS build keeps the localhost capture server; `network.server`/`network.client` entitlements).

Screenshots ready to upload: `marketing/app-store-screenshots/` — four 2560×1600 PNGs (a valid
Mac App Store size), ordered 01–04.

---

## Name (≤30 chars)
```
JobHunt — Find Your Next Job
```
(28 chars. Note: drop any stray trailing quote that crept into the App Store Connect field.)

## Subtitle (≤30 chars)
```
Capture, score & track jobs
```

## Promotional Text (≤170 chars — editable anytime without a new review)
```
Capture any job posting, let AI extract the details and score it against your resumes, then track every application — fast, native, and 100% on your Mac.
```

## Keywords (≤100 chars, comma-separated; no words already in Name/Subtitle)
```
application,tracker,career,resume,fit,AI,pipeline,interview,offer,salary,CRM,search,hiring,remote
```

## Description (≤4000 chars)
```
JobHunt is a fast, native Mac app for running your job search without a spreadsheet. Capture any job posting with one click, let AI pull out the details, and track every application from "Interested" to "Offer" — all on your own machine.

YOUR DATA STAYS YOURS
Everything lives in a local database on your Mac. Nothing is sent to any server except the AI provider you choose — and you can run that locally too, so your job search never leaves your computer. No account. No subscription. No cloud.

ONE-CLICK CAPTURE
Install the free companion Chrome extension and capture any job posting in a single click. Works on LinkedIn, Indeed, Greenhouse, Lever, Workday, Ashby, and more. A preflight check confirms the title, location, salary, and remote status were found before saving, and captures queue offline if the app isn't running.

AI THAT READS THE JOB FOR YOU
A language model reads each description and extracts structured fields automatically — salary bands, seniority, work mode, and requirements. Bring your own provider: LM Studio, Ollama, OpenAI, Anthropic, Google, OpenRouter, or any OpenAI-compatible endpoint. Run a free local model at zero cost, or use a paid cloud API — your choice.

KNOW WHICH ROLES FIT
Add one or more resumes — upload a PDF or paste text. Every job is scored against each resume with a 0–100 fit score and a plain-English explanation of what's missing, so you know which roles, and which resume, are worth pursuing.

TRACK YOUR WHOLE PIPELINE
Move jobs through Interested, Applied, Interview, and Offer. Set follow-up reminders, log notes on every interaction, and see your funnel at a glance on the dashboard.

POWERFUL FILTERING
Filter by status, salary, location, remote eligibility, fit score, or any combination. Sort by any column and save views for your most common searches.

DUPLICATE DETECTION
Automatically groups the same job posted across multiple boards so you never apply twice. Heuristic matching handles slight title and description variations.

AVAILABILITY CHECKS
Periodically re-checks saved jobs and lets you know when a posting you were watching has been taken down.

Built entirely in SwiftUI for macOS — lightweight, native, and a good Mac citizen.

Free and open source: https://github.com/brooksc/jobhunt
```

---

## URLs
| Field | Value |
|---|---|
| Marketing URL | `https://jobhunt-app.com` |
| Support URL | `https://github.com/brooksc/jobhunt/issues` |
| Privacy Policy URL | `https://jobhunt-app.com/privacy.html` |

## Categorization
| Field | Value |
|---|---|
| Primary category | Productivity |
| Secondary category | Business |
| Age rating | 4+ (no objectionable content) |

## Copyright
```
© 2026 Brooks Cutter
```

## Version / build
- **Version:** `1.0.1` (matches `Project.swift` `marketingVersion`)
- **Build:** taken from the tagged release (`CFBundleVersion` = `yymmddHHMM`, uint32-safe — see
  `release-mas.yml` "Compute build number"). For a real submission, build from a `v*` tag, not `main`.

---

## App Review notes (paste into "Notes" for the reviewer)
```
No account or sign-in is required; the app stores everything locally.

To exercise AI extraction and resume fit-scoring, configure a provider in
Settings > AI Provider (any OpenAI-compatible endpoint, or a free local model
via LM Studio or Ollama). Core job tracking works without AI configured.

The optional Chrome extension (separate, free) sends captured job postings to
the app over a localhost connection only. No user data leaves the device except
requests to the AI provider the user configures.

You can add a job manually from the toolbar, or paste a job description, to see
extraction and tracking without installing the extension.
```

## Privacy "nutrition label" answers (App Privacy section)
- **Data collection:** None. The developer does not collect any data.
  - The app has no analytics, no account system, and no first-party server.
  - Job text the user sends to a *user-configured, third-party* AI provider is governed by that
    provider's policy, not the developer's — disclose this in the Privacy Policy (already covered at
    `https://jobhunt-app.com/privacy.html`), but JobHunt itself collects nothing.
</content>
