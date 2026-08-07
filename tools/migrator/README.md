# JobhuntMigrator

One-time standalone CLI tool that migrates the legacy Electron-based `jobhunt.db` (SQLite) to a
SwiftData store usable by the native Jobhunt macOS app.

This tool is **not shipped** in the app. It is included in the DMG scheme for developer use only.

## Building it

```bash
./scripts/build-migrator.sh              # Debug-DMG (default)
./scripts/build-migrator.sh --config Release-DMG
```

The script prints the exact executable path and its build time. **Use it** rather than a bare
`xcodebuild` — there are two DerivedData trees, and getting this wrong is a data-integrity hazard, not
an inconvenience (TASK-652):

- `scripts/rebuild-and-run.sh` pins `-derivedDataPath ~/Library/Developer/Xcode/DerivedData/Jobhunt-local`.
- A bare `xcodebuild` writes to Xcode's default *hashed* path instead.

So `xcodebuild build -scheme JobhuntMigrator` reports **BUILD SUCCEEDED** while the binary you then run
from `Jobhunt-local` stays untouched — its mtime never moves, and it silently keeps running old logic.
That is exactly how `--recompute-fit-mirrors` once reported "0 job mirror(s) corrected" against 206
provably-wrong rows; a rebuilt binary corrected them immediately. Note `xcodebuild -target
JobhuntMigrator` is worse still: it reports success while emitting only a `.swiftmodule`, no executable.

The migrator prints its build time on every run, and warns when the binary is more than a day old:

```
JobhuntMigrator (built 2026-07-27 20:00)
```

If that timestamp predates a change you're relying on, rebuild before running anything against the
store. "0 corrected" and "already correct" look identical from the outside.


## Usage

```
JobhuntMigrator [--input <path>] --output <path>
```

### Options

| Option | Description | Default |
|---|---|---|
| `--input <path>` | Path to the legacy `jobhunt.db` SQLite file | `~/Library/Application Support/Jobhunt/jobhunt.db` |
| `--output <path>` | Path to write the new SwiftData store (required) | — |

## Store maintenance (operate on the live store)

These modes repair an existing SwiftData store in place. They are one-time data fixups that used to
run automatically on app launch; they now live here so the launch path stays clean. **Quit the
Jobhunt app first** — the store is single-writer (SQLite), and a second process touching it while the
app runs risks `SQLITE_BUSY` or corruption.

**Exactly one operation flag per run.** The migrator rejects an invocation that combines two operation
flags (or an operation flag with `--output`/migrate), rather than silently running the first in
priority order (TASK-523).

| Option | Description | Default store |
|---|---|---|
| `--reclean [--store <path>]` | Recompute every capture's `cleanedDescription` with the current cleaner (JSON-LD preference, boilerplate stripping, invisible-char scrubbing). Idempotent. | `~/Library/Application Support/Jobhunt/jobhunt.store` |
| `--backfill-models [--store <path>]` | Fill `LLMRequest.model` on older finished rows from their attempt history (so they don't render "—"). Idempotent; only touches rows with no model. | same |
| `--prune-orphan-fit-scores [--store <path>]` | Delete fit scores with no resume linked (legacy/unmigrated rows that render as a model name and hijack "Best match"), then recompute each affected job's denormalized fit mirror. | same |
| `--prune-orphan-referral-attempts [--store <path>]` | Delete referral attempts (and N/A markers) whose job no longer exists. `ReferralAttempt` is keyed by `jobID` with no SwiftData relationship, so jobs deleted before the cascade existed left theirs behind. | same |
| `--prune-orphan-attempts [--store <path>]` | Delete `LLMRequestAttempt` rows whose parent request is gone (historical orphans from prunes that predate the cascade delete rule). | same |
| `--recheck-evidence [--store <path>]` | Mark every stored requirement assessment whose quoted evidence appears in no résumé — either lifted from the posting or found nowhere. **Marks only; no score changes.** An exact-substring test can't tell invention from paraphrase (measured wrong 6 times in 7 against hand labels), so the user decides via "I don't have this". | same |
| `--recompute-fit-mirrors [--store <path>]` | Recompute every job's denormalized fit mirror (`fitScore`/`fitStatus`/`fitScoreJSON`) from its best resume-linked score; touches only drifted rows. | same |
| `--detect-duplicates [--store <path>]` | Run the app's duplicate detector and persist results (flag candidates with `duplicateOfJobID` + `.duplicate` status). Useful after a bulk `--reclean` changes cleaned hashes. Skips pairs resolved via DuplicateDecision. | same |
| `--merge-job --from <job#> --into <job#> [--store <path>]` | Fold a duplicate job into the one being kept, then delete the duplicate. Fills only fields the kept job is **missing** — never overwrites a populated or manually-overridden field — and leaves its status, notes and fit scores alone. Extraction provenance (`extractedJSON`/model/confidence/`extractedAt`/status) moves as one unit, and only when the kept job has no extraction of its own. The duplicate's capture is deleted with it, so merge only when both describe the same posting. Logs a `merge` timeline event on the kept job. **Not idempotent** — it deletes a row. | same |
| `--repair-duplicate-job-numbers [--store <path>]` | Renumber duplicate `jobNumber` rows (keep the oldest, reassign collisions to fresh `max+1` numbers) so the store can open under the `jobNumber` unique constraint. **Raw SQLite** — runs without opening the store via SwiftData, because a store with duplicates can't be opened. Non-destructive; idempotent. | same |

```bash
# Quit Jobhunt, then:
JobhuntMigrator --reclean
JobhuntMigrator --backfill-models
JobhuntMigrator --merge-job --from 761 --into 725   # keeps #725, deletes #761
```

### Example

```bash
# Migrate with default input path
JobhuntMigrator --output ~/Desktop/jobhunt.store

# Migrate from a specific backup copy
JobhuntMigrator \
  --input ~/Backups/jobhunt.db \
  --output ~/Desktop/jobhunt-migrated.store
```

### After migration

1. Quit the Jobhunt app if running.
2. Back up `~/Library/Application Support/Jobhunt/` (the existing store and any Derived data).
3. Copy the output `.store` file (and its `-shm` / `-wal` siblings if present) to
   `~/Library/Application Support/Jobhunt/jobhunt.store`.
4. Launch the Jobhunt app — it will open the migrated store.

## Unique constraints & store-open recovery

SwiftData enforces every `@Attribute(.unique)` field with a SQLite unique index, so a store that
holds duplicate values on a unique column **cannot be opened** (the app then shows the recovery UI —
it fails *closed*, never silently corrupting data). The full policy lives in
`core/Models/ModelContainerFactory.swift`; recovery per unique field:

| Unique field | Can a real store collide? | Recovery |
|---|---|---|
| `Job.jobNumber` | **Yes** — Electron `job_number` can repeat | `--repair-duplicate-job-numbers` (raw SQLite, pre-open; renumbers duplicates) |
| `Capture.rawHash` | No — it's the content-dedup key the source already enforces (and blind dedup would orphan jobs referencing a dropped capture) | n/a |
| `DuplicateDecision.cleanedHash` | No — natural key of the decision | n/a |
| `Site.origin` | No — natural site identity | n/a |
| `Setting.key` | No — KV-store key | n/a |
| `SavedSearch.id` | No — a UUID, not imported from Electron | n/a |

Only `jobNumber` has (and needs) a pre-open repair. For the others, a duplicate could only come from
an externally-modified store; if that ever happens for a real store, add a targeted, idempotent
`RepairJobNumbers`-style raw-SQLite repair for that specific field (runs **before** any
`ModelContainer` open) rather than a speculative one now — and keep recovery fail-closed in the
meantime.

## What is migrated

Every legacy SQLite table is mapped to a SwiftData `@Model`:

| Legacy table | SwiftData model |
|---|---|
| `captures` | `Capture` |
| `jobs` | `Job` |
| `events` | `JobEvent` |
| `site_reviews` | `SiteReview` |
| `duplicate_decisions` | `DuplicateDecision` |
| `settings` | `Setting` |
| `job_actions` | `JobAction` |
| `data_quality_reviews` | `DataQualityReview` |
| `sites` | `Site` |
| `resumes` | `Resume` |
| `job_fit_scores` | `JobFitScore` |
| `llm_requests` | `LLMRequest` |
| `llm_request_attempts` | `LLMRequestAttempt` |
| `contacts` | `Contact` |
| `cover_letters` | `CoverLetter` |

All `jobNumber`, `rawHash`, `cleanedHash`, timestamps, and JSON blobs are preserved verbatim.
ISO 8601 date strings from the legacy DB are parsed into `Date` values.

The input DB is opened **read-only**. The tool is idempotent when run into a fresh output path.

## Building

The migrator is part of the `Jobhunt-DMG` Xcode scheme. After running `tuist generate`:

```bash
xcodebuild \
  -scheme Jobhunt-DMG \
  -configuration Debug-DMG \
  -destination 'platform=macOS' \
  CODE_SIGNING_ALLOWED=NO \
  build
```

The binary is placed in `DerivedData/.../Build/Products/Debug-DMG/JobhuntMigrator`.
