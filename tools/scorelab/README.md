# ScoreLab

Compare fit-scoring variants over the real corpus, without launching the app.

```bash
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer \
  xcodebuild build -project Jobhunt.xcodeproj -scheme ScoreLab -configuration Debug-DMG \
  -destination 'platform=macOS' -derivedDataPath ~/Library/Developer/Xcode/DerivedData/Jobhunt-local \
  CODE_SIGNING_ALLOWED=NO

BIN=~/Library/Developer/Xcode/DerivedData/Jobhunt-local/Build/Products/Debug-DMG/ScoreLab
"$BIN"                          # whole corpus
"$BIN" --status Interested      # only jobs under active evaluation
"$BIN" --json /tmp/scores.json  # machine-readable, for an eval to consume
"$BIN" --store /path/to.store   # a copy, or the UI-test store
```

## Why it exists

Re-scoring is free — every analysis is stored as JSON, so a variant can be evaluated over hundreds of
real jobs in seconds with **no LLM calls**. Experiments used to live in throwaway scripts that
re-derived the arithmetic in another language, which is exactly the divergence this codebase has been
bitten by before (an independent base-score reimplementation disagreed with `FitScorer` by a point on
the first job). ScoreLab scores through `FitScorer.score(_:dimensions:assessments:)` — the same call
the app makes — so the variant that wins an experiment is the variant that ships.

Reads the store **read-only** (`SQLITE_OPEN_READONLY`), so it is safe to run while the app is open.
The store is single-writer; never point a writing tool at it.

## Reading the output

| Column | Means |
|---|---|
| `med` | median score |
| `>=90` | share at 90+ — a proxy for compression at the top |
| `40-80` | share in the band where triage decisions actually get made |
| `top30` | **distinct score values among the top 30 jobs** |
| `sd` | spread across the corpus |
| `rho` | Spearman rank correlation against the current shipped scheme |

`top30` is the one to watch. A whole-corpus tie rate is useless for comparing variants — with
hundreds of jobs over ~100 possible values it sits above 97% for everything. What matters is
resolution *at the top*, because that is where the list is used to decide which job to spend an
evening applying to. A variant can be perfectly stable and still be useless if the top 30 all share
one score.

The `clean median vs missing-required median` lines are the other half: jobs missing a hard
requirement should sit clearly below jobs missing none.

## Variants

Defined in `core/Services/ScoringVariant.swift`:

- **`.current`** — shipped: weighted dimensions minus the normalised penalty. Two independent LLM
  judgements feed it (five dimension numbers *and* the per-requirement verdicts), so it carries two
  independent sources of run-to-run variance.
- **`.verdictShare`** — share of requirements met, nothing else. Deterministic given the verdicts,
  but compresses badly: requirement lists are generous, so the top of the list collapses.
- **`.hybrid`** — the share blended with only `domain_fit` and `experience_level`, the two judgements
  a requirement list structurally cannot express (no posting has a bullet reading "must have worked
  in our industry").
