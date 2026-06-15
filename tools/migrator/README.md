# JobhuntMigrator

One-time standalone CLI tool that migrates the legacy Electron-based `jobhunt.db` (SQLite) to a
SwiftData store usable by the native Jobhunt macOS app.

This tool is **not shipped** in the app. It is included in the DMG scheme for developer use only.

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

| Option | Description | Default store |
|---|---|---|
| `--reclean [--store <path>]` | Recompute every capture's `cleanedDescription` with the current cleaner (JSON-LD preference, boilerplate stripping, invisible-char scrubbing). Idempotent. | `~/Library/Application Support/Jobhunt/jobhunt.store` |
| `--backfill-models [--store <path>]` | Fill `LLMRequest.model` on older finished rows from their attempt history (so they don't render "—"). Idempotent; only touches rows with no model. | same |
| `--prune-orphan-fit-scores [--store <path>]` | Delete fit scores with no resume linked (legacy/unmigrated rows that render as a model name and hijack "Best match"), then recompute each affected job's denormalized fit mirror. | same |
| `--prune-orphan-attempts [--store <path>]` | Delete `LLMRequestAttempt` rows whose parent request is gone (historical orphans from prunes that predate the cascade delete rule). | same |
| `--recompute-fit-mirrors [--store <path>]` | Recompute every job's denormalized fit mirror (`fitScore`/`fitStatus`/`fitScoreJSON`) from its best resume-linked score; touches only drifted rows. | same |
| `--detect-duplicates [--store <path>]` | Run the app's duplicate detector and persist results (flag candidates with `duplicateOfJobID` + `.duplicate` status). Useful after a bulk `--reclean` changes cleaned hashes. Skips pairs resolved via DuplicateDecision. | same |

```bash
# Quit Jobhunt, then:
JobhuntMigrator --reclean
JobhuntMigrator --backfill-models
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
