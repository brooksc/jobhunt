# JobhuntMigrator

Standalone developer CLI for **one-time data fixups on the live Jobhunt SwiftData store**. Per
project convention such work lives here rather than in the app's launch path: the store is
single-writer, so a fixup must run deliberately, out-of-band, with the app quit.

This tool is **not shipped** in the app. It is included in the DMG scheme for developer use only.

> The original Electron `jobhunt.db` → SwiftData import (`--migrate` / `--verify` / `--patch` /
> `--patch-fit-scores` / `--repair-fit-scores`) has been removed. It ran once, years ago, for the
> only install that ever needed it.

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

## Store maintenance (operate on the live store)

These modes repair an existing SwiftData store in place. They are one-time data fixups that used to
run automatically on app launch; they now live here so the launch path stays clean. **Quit the
Jobhunt app first** — the store is single-writer (SQLite), and a second process touching it while the
app runs risks `SQLITE_BUSY` or corruption. The tool enforces this with a `pgrep` check and refuses
to run if the app is up.

**Exactly one operation flag per run**, and there is no default: an invocation with no operation flag,
or one combining two, is rejected rather than silently running the first in priority order (TASK-523).

The default store for every mode is `~/Library/Application Support/Jobhunt/jobhunt.store`; pass
`--store <path>` to target another.

| Option | Description |
|---|---|
| `--reclean` | Recompute every capture's `cleanedDescription` with the current cleaner (JSON-LD preference, boilerplate stripping, invisible-char scrubbing). Idempotent. |
| `--backfill-models` | Fill `LLMRequest.model` on older finished rows from their attempt history (so they don't render "—"). Idempotent; only touches rows with no model. |
| `--prune-orphan-fit-scores` | Delete fit scores with no resume linked (legacy rows that render as a model name and hijack "Best match"), then recompute each affected job's denormalized fit mirror. |
| `--prune-orphan-referral-attempts` | Delete referral attempts (and N/A markers) whose job no longer exists. `ReferralAttempt` is keyed by `jobID` with no SwiftData relationship, so jobs deleted before the cascade existed left theirs behind. |
| `--prune-orphan-attempts` | Delete `LLMRequestAttempt` rows whose parent request is gone (historical orphans from prunes that predate the cascade delete rule). |
| `--normalize-seniority` | Collapse stored `seniority` onto the canonical bands (intern/entry/mid/senior/lead/staff/principal/manager/director/executive). Values carrying no level — "5+ years", "III" — become null rather than a guessed band, because that text feeds the fit-scoring prompt's `experience_level` dimension. Idempotent. |
| `--repair-salaries` | Fix salary bands the old range parser invented. Until the parser required affirmative pay evidence, any two dash-separated numbers over 1,000 became a band — job #1502 (SageSure) states no pay yet stored $2,020–$2,023 from "Best Places to Work in Insurance … (2020-2023)". **Only acts on a stored band the evidence can't account for** — neither end appears as a money amount in the job's `salaryNote` + cleaned description, which is exactly the shape the old pattern manufactured. Such a band is re-parsed (the posting states pay elsewhere) or cleared (it states none). A job with **no** salary is never given one, and a supported band is left alone even if re-parsing would choose differently: both would be bulk re-extraction, not repair. Never touches a manually-overridden salary field. Idempotent. |
| `--recheck-evidence` | Mark every stored requirement assessment whose quoted evidence appears in no résumé — either lifted from the posting or found nowhere. **Marks only; no score changes.** An exact-substring test can't tell invention from paraphrase (measured wrong 6 times in 7 against hand labels), so the user decides via "I don't have this". |
| `--recompute-fit-mirrors` | Recompute every job's denormalized fit mirror (`fitScore`/`fitStatus`/`fitScoreJSON`) from its best resume-linked score; touches only drifted rows. |
| `--recompute-criteria` | Re-judge every job against the current location/remote settings and rewrite its `meetsCriteria` mirror. Run after changing preferred locations or metros. |
| `--detect-duplicates` | Run the app's duplicate detector and persist results (flag candidates with `duplicateOfJobID` + `.duplicate` status). Useful after a bulk `--reclean` changes cleaned hashes. Skips pairs resolved via DuplicateDecision. |
| `--unmark-heuristic-duplicates` | Un-mark and restore jobs that were flagged as duplicates by the old fuzzy heuristic, keeping only definitive same-posting duplicates (TASK-622). |
| `--repair-canonical-urls` | Clear a capture's stored canonical URL when it doesn't identify the posting (a site-root or search URL), so it can't merge unrelated jobs. |
| `--merge-job --from <job#> --into <job#>` | Fold a duplicate job into the one being kept, then delete the duplicate. Fills only fields the kept job is **missing** — never overwrites a populated or manually-overridden field — and leaves its status, notes and fit scores alone. Extraction provenance (`extractedJSON`/model/confidence/`extractedAt`/status) moves as one unit, and only when the kept job has no extraction of its own. The duplicate's capture is deleted with it, so merge only when both describe the same posting. Logs a `merge` timeline event on the kept job. **Not idempotent** — it deletes a row. |
| `--repair-duplicate-job-numbers` | Renumber duplicate `jobNumber` rows (keep the oldest, reassign collisions to fresh `max+1` numbers) so the store can open under the `jobNumber` unique constraint. **Raw SQLite** — runs without opening the store via SwiftData, because a store with duplicates can't be opened. Non-destructive; idempotent. |

```bash
# Back up the store WITH its -wal and -shm, quit Jobhunt, then:
JobhuntMigrator --reclean
JobhuntMigrator --backfill-models
JobhuntMigrator --merge-job --from 761 --into 725   # keeps #725, deletes #761
```

## Unique constraints & store-open recovery

SwiftData enforces every `@Attribute(.unique)` field with a SQLite unique index, so a store that
holds duplicate values on a unique column **cannot be opened** (the app then shows the recovery UI —
it fails *closed*, never silently corrupting data). The full policy lives in
`core/Models/ModelContainerFactory.swift`; recovery per unique field:

| Unique field | Can a real store collide? | Recovery |
|---|---|---|
| `Job.jobNumber` | **Yes** — historical rows imported from the retired app can repeat | `--repair-duplicate-job-numbers` (raw SQLite, pre-open; renumbers duplicates) |
| `Capture.rawHash` | No — it's the content-dedup key ingest already enforces (and blind dedup would orphan jobs referencing a dropped capture) | n/a |
| `DuplicateDecision.cleanedHash` | No — natural key of the decision | n/a |
| `Site.origin` | No — natural site identity | n/a |
| `Setting.key` | No — KV-store key | n/a |
| `SavedSearch.id` | No — a UUID | n/a |

Only `jobNumber` has (and needs) a pre-open repair. For the others, a duplicate could only come from
an externally-modified store; if that ever happens for a real store, add a targeted, idempotent
`RepairJobNumbers`-style raw-SQLite repair for that specific field (runs **before** any
`ModelContainer` open) rather than a speculative one now — and keep recovery fail-closed in the
meantime.

## Adding a mode

Put the transformation in `BackgroundStore` (or elsewhere in JobhuntCore) with a unit test, then add
a `Mode` case + flag parsing in `Args.swift`, a handler in `main.swift`, and a row in the table above.
Once every install has passed a given fixup, delete the mode.

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
