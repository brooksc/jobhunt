# Jobhunt — the normal workflow

Jobhunt tracks one person's job search on one Mac — on the order of a few hundred jobs. The day-to-day
loop is the same for every job posting you come across:

> **capture → dedup & create → auto AI processing → review → resolve**, repeated per posting.

This doc is the end-to-end narrative of that loop and which part of the app owns each step. Where
today's behavior differs from the intended UX, it's called out inline with the backlog task that
closes the gap.

```
   Browser (Chrome extension)                 Jobhunt.app (local)
   ─────────────────────────                  ───────────────────
   click "Capture job"  ──HTTP──▶  localhost server (ports 8765–8769)
                                        │
                                        ▼
                                   JobService.ingestCapture
                                   validate → clean → hash → DEDUP
                                        │  (new posting)
                                        ▼
                                   Job (status: new) + Capture + pending extraction request
                                        │
                                        ▼
                                   QueueActor.startProcessing  (automatic, continuous)
                                   extraction ──▶ auto fit-scoring vs active resume(s)
                                        │
                                        ▼
                                   "ready to review" notification  ──click──▶ opens the job
                                        │
                                        ▼
                                   You: read, set status, add notes
                                        │
                                        ▼
                                   Resolve: archived / rejected / passed / expired / closed
```

---

## 1. Capture from the browser

You find a job description on any page and send it to Jobhunt with the **Chrome extension**:

- **Toolbar button** ("Capture job") — captures the current page. A preflight dialog confirms what was
  detected (title, location, salary, remote status) before saving.
- **Right-click menu** — "Save job with note" (capture with a personal note), "Mark site reviewed", and
  "Open capture queue".

The extension POSTs the captured content to the app's **local HTTP server**, which probes
`127.0.0.1:8765`–`8769` to find the running instance. If the app isn't running, the capture is stored
in the extension's **offline queue** and synced automatically the next time you capture while the app
is reachable (or on demand from the capture-queue page). Nothing is sent to any remote server — only to
your local app.

## 2. Ingest & dedup → a new Job

The server hands the capture to `JobService.ingestCapture`, which:

1. **Validates** the URL (one shared URL policy — non-`http(s)`/malformed captures are rejected before
   anything is persisted).
2. **Cleans** the page text (strips boilerplate/serialized app blobs) into the job description.
3. **Hashes** the raw and cleaned content and **deduplicates** — by raw hash, cleaned hash, and URL.
4. For a **new** posting, atomically creates a **Job** (status `new`), its **Capture**, and a **pending
   extraction request**. (A content duplicate is recorded as such and creates no second job; the
   capture returns `isDuplicate`.)

So step 2 of your workflow ("added if it's new") is dedup-by-construction — re-capturing the same
posting won't create duplicate jobs.

## 3. Automatic AI processing

The `QueueActor.startProcessing` loop runs continuously and **picks up the pending extraction request
on its own** — no manual action needed. For each job it:

1. **Extracts** structured fields (company, title, location, salary, remote type, seniority, skills,
   requirements, summary, …) using your configured LLM.
2. **Auto-scores fit** against your **active resume(s)** immediately after a successful extraction
   (no-op if you have no active resume).

**This requires a configured AI provider** (Settings → AI Provider; the API key lives in the macOS
Keychain) **and, for fit scoring, at least one active resume.**

- **No provider configured:** *(target — TASK-483)* you get an immediate notice when a capture lands —
  "Job captured ✓ — set up an AI provider to enable extraction & fit scoring" — deep-linking to AI
  Provider settings. *Today* this is reactive instead: the request fails on each attempt and, after a
  run of failures, the queue **auto-pauses** with a critical "AI Queue Paused" notification that
  deep-links to the **LLM Queue** view.
- **Provider failing at runtime** (bad key, outages, rate limits): transient rate-limits back off and
  retry; sustained failures auto-pause the queue (critical notification → LLM Queue). Rate-limit bursts
  and user cancellations deliberately don't count toward auto-pause.
- **Manual kick:** you can always run processing yourself — "Re-run AI Extraction" from the toolbar /
  right-click menu, the **LLM Queue** view, or Data Quality → "Queue Re-extraction".

## 4. "Ready to review" notification

When a job finishes extraction + fit, Jobhunt emits a `jobReady` event and notifies you.

- **Target (TASK-482):** one **"ready to review"** notification per completed job, regardless of fit
  score, with **strong matches (fit ≥ 75%)** highlighted as **"Strong Match!"**.
- **Today:** only strong matches notify individually; a single sub-75% job is silent, and a batch of
  several jobs is summarized as "N jobs processed" at the end of the run.

Supporting cues, regardless of the above:
- The **Dock badge** shows the unread-job count.
- **Clicking** a notification activates the app and deep-links straight to that job
  (`jobhunt://jobs/<number>` under the hood).
- If the **availability checker** later finds a posting is gone, it posts a **"Job Unavailable"**
  notification (see step 6).

## 5. Review & track

Open the job (from the notification, the Jobs list, or ⌘K → All Jobs) and work it:

- Read the extracted **summary, skills, requirements**, and the **fit score + per-dimension rationale**
  against your resume(s).
- Move it through the **status lifecycle** as things progress:
  `new → pursuing → applied → interview → offer`.
- Add **notes**, a **rating**, **contacts**, and **cover letters** along the way.

All of this is a single user's data on one machine — filtering/sorting a few hundred jobs is instant.

## 6. Resolve — and repeat

Eventually each job reaches a terminal state. Set its status to one of:

- **`rejected`** / **`passed`** — you were turned down, or you decided to pass.
- **`archived`** — done with it, keep it for the record. (Archived jobs stay visible in **All Jobs**;
  their chip just reads "Archived".)
- **`expired`** — the posting is no longer live. The **availability checker** periodically re-checks
  open jobs' URLs; postings it detects as gone (expired/filled/closed) are surfaced for confirmation
  and marked **`expired`**, with a "Job Unavailable" notification.
- **`closed`** — the role closed generally.

Then you move on to the next posting and the loop repeats.

---

## Prerequisites (one-time setup)

1. **Install & launch the Jobhunt Mac app** (it runs the local server and the AI queue).
2. **Configure an AI provider** — Settings → AI Provider (key stored in the Keychain). Without this,
   extraction and fit scoring can't run (see step 3).
3. **Add a resume** and mark it active — required for fit scoring (step 3); without one, jobs still
   extract but get no fit score.
4. **Install the Chrome extension** — it connects to the app over `localhost`; the MCP/capture token is
   generated automatically by the app.

## Related docs

- **Backups & data store:** see [CLAUDE.md](../CLAUDE.md) → "Data store location & backup".
- **AI providers / structured output:** `core/LLM/` (providers, `QueueActor`, `ExtractionEngine`,
  `FitScorer`).
- **UI test coverage of these flows:** `tests/AppUITests/WorkflowUITests.swift` (archive workflow) and
  [docs/vm-testing.md](vm-testing.md).

## Gaps tracked against this doc

- **TASK-482** — per-job "ready to review" notification (highlight strong matches). *(step 4)*
- **TASK-483** — upfront "no AI provider configured" notice at capture time. *(step 3)*
