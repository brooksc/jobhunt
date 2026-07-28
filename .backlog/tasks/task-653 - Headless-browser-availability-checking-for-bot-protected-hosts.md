---
id: TASK-653
title: Headless-browser availability checking for bot-protected hosts
status: On Hold
assignee: []
created_date: '2026-07-28 18:04'
labels:
  - availability
  - spike
  - large
dependencies: []
references:
  - core/Services/AvailabilityChecker.swift
  - docs/release-process.md
priority: low
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
## Problem

`AvailabilityChecker` uses plain `URLSession` requests. Hosts behind Cloudflare (and similar) never serve the real page to it — they return HTTP 403 with a `Just a moment...` interstitial. `isBotChallenge(_:)` correctly classifies these as **indeterminate** rather than "gone", so those jobs can never be auto-detected as expired.

Confirmed case: job #164 (New Relic, remoterocketship.com) — `HTTP 403`, `<title>Just a moment...`, no gone-signal markers. The user marked it expired by hand. Note the page requires **no login** — a real browser loads it fine. The blocker is bot detection, not authentication.

Known affected hosts in the current library: `remoterocketship.com`, `pinterestcareers.com` (Phenom), plus LinkedIn (a separate problem — LinkedIn *does* gate on login, and is explicitly out of scope for scraping given account-ban risk).

## Proposal (to evaluate, not yet approved)

Run a headless Chromium (Playwright, plus a stealth/evasion plugin) in the background to fetch these pages, and feed the resulting HTML into the existing gone-signal detection. The user reports good results with this combination.

## Assessment

**Why it's attractive:** it fixes the whole class in one move rather than per-host, and it reuses the existing `isBotChallenge` / gone-marker logic downstream — only the *fetch* changes, so blast radius is small if it's kept behind a clean seam.

**Why it's expensive — the real costs are packaging and lifecycle, not the automation:**

1. **Distribution.** Chromium is ~150–200 MB and Playwright is a Node runtime. Jobhunt today is a self-contained Swift app; bundling either roughly doubles the DMG and adds a Node dependency the project otherwise doesn't have. Downloading on first use instead means a network install, a cache dir to manage, and a new failure surface.
2. **MAS is almost certainly a non-starter.** The App Sandbox forbids spawning arbitrary child executables and downloading+executing code. This would realistically be **DMG-only**, making the two channels behave differently — worth deciding deliberately, since it's the first such divergence.
3. **Hardened runtime / notarization.** A bundled Chromium needs its own signing and probably entitlements; `notarytool` will scrutinize it. Non-trivial addition to `release-dmg.yml`.
4. **Lifecycle.** Headless browsers hang, leak, and zombie. Needs hard timeouts, process reaping on app quit (cf. the `AppServices.shutdown()` quiescing work in TASK-546), and a concurrency cap so a scheduled run can't spawn N browsers.
5. **Arms race.** Stealth plugins work until they don't; this is maintenance that never ends, and a silent regression looks identical to "job still live".
6. **Ethics/ToS.** Evading bot detection is a deliberate choice. Low risk for a single user reading public job pages at low volume (and materially different from the LinkedIn case, which risks a personal account), but it should be a conscious decision, and rate limits must be conservative.

**Cheaper alternatives to weigh first:**
- **Authoritative ATS lookup** (overlaps TASK-648): resolve the posting to its source board (Greenhouse/Lever/Ashby/Workday) and query that API. Definitive, cheap, no browser, no evasion — but only covers postings whose ATS we can identify. It would *not* have solved #164 without mapping remoterocketship → New Relic's own board.
- **Surface indeterminacy in the UI.** Today a bot-challenged job is silently skipped, which reads as "checked and fine" — that's why the user assumed detection had failed. A "couldn't verify — check manually" state is a small change that recovers most of the practical value.
- **`WKWebView`** instead of Chromium: already in the OS, no bundling, no Node, sandbox-compatible. Weaker against fingerprinting than a stealth-patched Chromium, but worth a spike — it may clear Cloudflare's basic JS challenge, which is what these hosts appear to use.

## Recommendation

Do the **cheap two first** (surface indeterminacy; spike `WKWebView`) and measure how many hosts actually remain unresolved. Only reach for bundled Chromium if that residue is both large and valuable — the packaging/MAS cost is the dominant term, and it is paid permanently.

## Acceptance criteria (if pursued)

Left deliberately staged — the spike gates the build.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Spike: measure how many currently-unresolvable hosts a plain WKWebView fetch can resolve, vs headless Chromium
- [ ] #2 Decision recorded on whether this is DMG-only, and what MAS does instead
- [ ] #3 Fetching is behind a seam so gone-signal detection is unchanged and still unit-testable without a browser
- [ ] #4 Hard per-page timeout and a concurrency cap; no browser process survives app quit
- [ ] #5 Availability UI distinguishes 'could not verify' from 'checked, still live'
- [ ] #6 Rate limiting is conservative and per-host
<!-- AC:END -->
