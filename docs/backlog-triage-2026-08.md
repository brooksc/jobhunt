# Backlog triage — 2026-08

Classifies every open task as **WORK** or **PARK** for the "clear everything practical" run.

A task is PARK only with a named blocker:

- **(a)** a product decision that materially changes behaviour and has no defensible default
- **(b)** acceptance that can only be judged visually
- **(c)** a credential, account or third party that is absent
- **(d)** another agent or person owns it

"Large" and "hard" are not blockers. Where only *part* of a task is blocked, the task is WORK and the
blocked acceptance criterion is rewritten to begin `not verified:` with the reason — the work still
lands, and nothing is silently claimed.

Out of bounds throughout: releases, MAS/App Store Connect, re-recording the demo, and anything that
drives the screen (screenshots, AppleScript, `open`, AppUITests). Several tasks below are therefore
implementable but not *visually* confirmable; they are WORK with a parked criterion, not PARK.

## PARK (5)

| Task | Blocker | What unblocks it |
|---|---|---|
| 503 — Sites review workflow clarity + Data Quality inline fixes | (a) | It asks for a workflow redesign with no stated target behaviour. Needs the user to say what the Sites screen is *for* before code can be right. |
| 655 — MCP setup undiscoverable in the DMG | (a) | The user deferred the design explicitly ("we'll figure out the design later"). Needs a decision between registering from the app vs documenting it. |
| 480 — SchemaV2 readiness: snapshot V1 + golden migration test | (a) | Gated on the first breaking model change, which hasn't happened. Do it *with* that change, not before — a snapshot of a schema that then moves is worse than none. |
| 500 — Cut Contacts & Cover Letters | (a) | Removal is a breaking schema change and a product call about dropping features. Pairs with 480. |
| 653 — Headless-browser availability checking | (a) | Adds a browser runtime to a local-first Mac app — a material architecture and footprint decision, not a routine call. |

## WORK (43, including 671 created during the run)

Ordered as the goal requires: correctness bugs, then scoring, then features; cheapest first.

### Correctness bugs

| Task | Note |
|---|---|
| 667 — Queue toolbar button always reads "Resume Queue" | Already diagnosed: bound correctly but disabled because `queueCommands` was never published. |
| 660 — Fit ring stale after a correction | Suspect the same observation/identity class as the row-height bug fixed in `dbdebd7d`. |
| 647 — Flaky ServerTests after the >1MB capture test | Test-only; poisons the next request. |
| 586 — SettingsStore.set swallows keychain write failure | |
| 614 — Fit scores from inactive resumes still shown | |
| 651 — Remote roles bypass geography criteria | "Remote — Europe/Colombia" reads as meeting criteria. |
| 657 — LLM queue orphan reaper | **Done.** Deadline + stale-drain supersede landed earlier; the reaper landed here. The barrier half was split to 671 rather than held behind it. |
| 671 — batch barrier → continuous dispatch | Split out of 657 during this run. WORK, not a parking place: a split only justifies landing the safe half first, not shelving the rest. |
| 548 — Start Fresh not atomic or failure-visible | Destructive path; test hard. |
| 514 — Queued captures with permanent server rejections | |
| 587 — Loopback binding is the real security boundary, not CORS | Document or enforce. |
| 593 — Pre-existing KeyPath-Sendable warnings | Was On Hold; it's a build-verifiable cleanup, so it qualifies. |

### Scoring

| Task | Note |
|---|---|
| 668 — OverCreditEval fails for every model | Partly addressed in `34b01365`; confirm and finish. Needs eval keys. |
| 661 — Measure model consistency | The 41–53 spread observed on one posting during the v1.4.0 recordings is the reason this outranks 669. Needs eval keys; capped spend. |
| 669 — partial→met over-crediting | **Partial.** Blind second labelling batch is PARK(d) — the résumé agent owns it. Do the prompt + measurement half against the existing 20 labels. |
| 650 — Normalize seniority (55 free-text values) | Pollutes fit scoring. |
| 659 — Route "I do have this" to the résumé | Blast-radius preview already shipped; routing half has a defensible default (surface it as a résumé suggestion). |

### Features and polish

| Task | Note |
|---|---|
| 658 — Queue Queued/Completed time column | |
| 664 — DeepSeek as a first-class provider | |
| 663 — Surface the model recommendation | Onboarding + Settings → AI. Visual check parked. |
| 654 — Scoring-corrections list editable and legible | Visual check parked. |
| 524 — Banner when the queue auto-pauses | Visual check parked. |
| 591 — Company/title autocomplete | |
| 502 — Needs Action: snooze date, cost clarity, price validation | Defensible defaults exist for each. |
| 632 — Refresh from the Greenhouse Job Board API | |
| 633 / 634 / 635 / 636 — ATS: freshness, other roles, form preview, beyond Greenhouse | 636 generalises the other three; do it last of the four. |
| 648 — MCP ATS-identifier resolution | Verifying the helper inside a notarized DMG needs a release → that criterion becomes `not verified`. |
| 627 — Custom Prompt AI templates | Defensible default: the variables already used by the existing tailored-résumé prompt. |
| 623 — Dashboard daily accomplishments *(In Progress)* | Finish or explicitly re-park. |
| 589 — Notify when a follow-up becomes due | Delivery is verifiable; the banner appearing is not. |
| 590 — Spotlight indexing | Index writes are verifiable; system search results are not. |
| 508 — Persist UI state across launches | Persistence is unit-testable; restoration appearance is not. |
| 557 — Min window size from a lifecycle hook | Logic verifiable; geometry not. |
| 506 — VoiceOver composite labels | Composed string is unit-testable; VoiceOver output is not. |
| 494 — Tooltips on icon-only controls | Auditable by search rather than by eye. |
| 665 — Model menu type-select | Keyboard handling; behaviour under a real menu is not verifiable. |
| 489 — Auto-launch from the extension | Protocol side is testable; the app actually launching is not. |
| 570 — Wire remaining static-analysis gates into CI | Periphery, warnings, analyze, ShellCheck, a11y. |
| 575 — Staple the notarization ticket to the .app | Implementable; only a real release proves it → `not verified`. |
| 619 — Safari and Firefox extensions | **Partial.** Firefox port is buildable. The Safari target and both store submissions are PARK(c) — no signing identity or AMO/Apple account access. |

## Progress — updated 2026-08-09

35 of the 43 WORK tasks are Done. The 13 tasks still open, and their classification as of this
update:

| Task | Class | State |
|---|---|---|
| 503 — Sites review workflow clarity | **PARK (a)** | Unchanged. Needs the user to say what the Sites screen is for. |
| 655 — MCP setup undiscoverable in the DMG | **PARK (a)** | Unchanged. Design deferred by the user. |
| 570 — Static-analysis gates | **WORK** | ShellCheck + a compiler-warning ratchet landed. Periphery, `swiftlint analyze` and the a11y audit remain. |
| 648 — MCP ATS-identifier resolution | **WORK** | #1–#3 done. #4/#5 rewritten `not verified: requires a notarized DMG` — cutting a release is out of bounds. |
| 665 — Model menu type-select | **WORK** | Not started. |
| 494 — Tooltips on icon-only controls | **WORK** | Not started. |
| 506 — VoiceOver composite labels | **WORK** | Not started. |
| 590 — Spotlight indexing | **WORK** | Not started. |
| 627 — Custom Prompt AI templates | **WORK** | Not started. |
| 623 — Dashboard daily accomplishments | **WORK** | Not started (still In Progress from before the run). |
| 489 — Auto-launch from the extension | **WORK** | Not started. |
| 619 — Safari/Firefox extensions | **WORK (partial)** | Buildable port only; store submissions PARK (c). |
| 575 — Staple the notarization ticket | **WORK** | Workflow change is implementable; proof needs a release → `not verified`. |

Nothing has moved from WORK to PARK during the run. Where a task turned out to be partly blocked, the
blocked *criterion* was rewritten `not verified: <reason>` and the rest landed, per the rule above.

## Standing risks for this run

- **SwiftFormat must be the pinned 0.61.1.** Homebrew's 0.62.1 disagrees (110 files vs CI's 18);
  formatting with it churns files CI rejects. This is how `main` stayed red from 2026-08-01 to
  2026-08-07.
- **The coverage floor is 70% lines.** New code without tests fails the build, so tests are not
  optional even for small changes.
- **Scoring changes cannot be validated by re-scoring stored JSON** when they alter the prompt — that
  needs fresh LLM calls over the labelled set.
