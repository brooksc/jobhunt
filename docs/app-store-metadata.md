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

## What's New in This Version (≤4000 chars — rewritten every submission)

Unlike everything above, this field is **per-release**, so treat the block below as the copy for the
submission named in its heading and replace it wholesale next time.

Two things make it differ from the GitHub release notes rather than being a copy of them:

1. **MAS skips releases.** Delivery to App Store Connect is curated (see
   [`release-process.md`](release-process.md#5-mac-app-store-mas-release) §5), so App Store users
   jump from the last `mas-v*` tag to this one. Cover *every* version in between —
   `git log $(git describe --tags --match 'mas-v*' --abbrev=0)..HEAD --oneline` — not just the
   newest. Check what the last delivered version actually was; it is **not** the previous DMG tag.
2. **The MAS build is a different product.** Omit anything the App Store build doesn't have: the
   **MCP integration** (no helper in the sandbox) and the **Sparkle auto-update** line (updates come
   from the App Store; Sparkle is excluded via `TUIST_MAS_ONLY=1`).

Plain text only - the field renders no Markdown. Match the existing listing's
convention: ALL-CAPS section headers, `-` for bullets.

**Never use `<` or `>` here.** They read as HTML tags, and App Store Connect refuses the whole field
with only *"This field contains one or more invalid characters"* to go on - it names neither the
character nor the offset, so the cause is easy to misattribute. Write "Settings / Jobs / Requirements"
rather than "Settings > Jobs > Requirements", and "below your minimum of 50" rather than "< 50".
(That error cost three rejections in the 1.3.0 submission: `<` was the culprit from the first
attempt, but the visible suspects were non-ASCII, so `→`, `•` and the em dash were stripped
first - and replacing `→` with `>` added two more offenders. The em dash and bullet are very
likely fine; they went untested once ASCII worked.)

Check before pasting:

```bash
python3 - <<'EOF'
s = open('/tmp/whatsnew.txt').read()
print('non-ascii:', sorted({c for c in s if ord(c) > 127}))
print('angle brackets:', s.count('<') + s.count('>'))
print('chars:', len(s), '(limit 4000)')
EOF
```

### 1.3.0 — accepted by App Store Connect (covers 1.2.0 + 1.3.0; last delivered was `mas-v1.1.3`)
```
WHAT YOU'LL ACCEPT, IN YOUR OWN NUMBERS
Settings / Jobs / Requirements now takes a minimum salary and a minimum fit score. Jobs sort into Meets, Not stated and Doesn't meet against everything at once - location, pay and fit - so a long Interested list narrows to what's worth applying to. Both start switched off; nothing is filtered until you set your own numbers. A job's badge says which requirement it missed ("Outside criteria: fit 44, below your minimum of 50") instead of leaving you to guess.

A posting that doesn't publish a salary is never rejected for it. Missing information isn't a failure, so those land in Not stated for you to look at separately.

TELL JOBHUNT WHEN IT SCORES YOU WRONG
Every requirement in a job's Fit tab now has a small flag. Click it and say "I do have this", "I don't have this", or "This isn't a real requirement". The correction applies to every job from then on, instantly, with no AI call and no cost. Everything you've corrected is listed under Settings / Jobs / Scoring Corrections, where removing it puts the scores straight back.

FIT SCORES ARE MARKEDLY LESS CREDULOUS
They were rewarding experience merely adjacent to what a job asked for, which put almost everything in the high eighties and nineties.
- A posting naming a specific technology, standard or certification now needs your resume to actually name it. Related work counts as a partial match, not a full one.
- Where a requirement lists alternatives, JobHunt weighs the one the posting is really about.
- Domain fit now means the industry and the product, not how transferable your skills are.
- Requirements nobody could fail - "capacity to learn Jira", "alignment with our values" - no longer count against you.
- A bullet asking for two different things is assessed as two requirements, so meeting one and missing the other is visible instead of averaging into a vague "partial".
Expect some scores to drop. That's the point: a list where everything scores 95 can't tell you where to spend your time.

REMOTE NOW MEANS REMOTE SOMEWHERE YOU CAN WORK
A remote role used to be accepted no matter where remote was offered, so Europe-only postings sat in your list looking qualified. Vague ("Global") or multi-region postings still pass - the check only rules out what it can positively identify as out of bounds. Changing your location settings also re-checks the jobs you already have, which costs no AI credit.

FIXED
- Salary missing from postings that clearly state one. Several separate causes, including pay written without a currency symbol, "$153K" rather than "$153,000", and ranges published apart from the structured job data and then discarded. Already-captured jobs can be repaired without re-capturing.
- Jobs from search-style boards overwriting each other. On sites that show a posting in a side pane while you browse - Microsoft careers, levels.fyi - every job claimed the same underlying address, so capturing a second one silently replaced the first.
- Microsoft roles not showing as remote, where the arrangement is stated as "0 days / week in-office" rather than the word "remote".
- Removed Greenhouse jobs going unnoticed, so a closed posting could sit in your list indefinitely.
- Availability checks now report how many jobs they verified and why the rest couldn't be, instead of an all-clear they hadn't earned.

ALSO
Duplicate postings are flagged before any AI scoring is spent on them. Adding a URL you already track tells you so instead of quietly overwriting. Control-Command-I marks a job Interested, alongside Control-Command-A to archive. The dock badge counts only jobs actually awaiting review. Manually added jobs start in New so you can review the fit first. Requirement text can be selected and copied, and salary shows its currency.
```

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
