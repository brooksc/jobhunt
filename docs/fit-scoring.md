# How a fit score is produced

A fit score is one number, 0–100, for a **(job, résumé) pair**. It is not one thing the model returns: it is a weighted average of five model-supplied dimension numbers, minus a penalty computed in Swift from a second, independent set of model judgements about individual requirements. Understanding which half is which is the point of this document, because they are tuned by completely different means — the dimension numbers move only by changing the prompt or the model, the penalty moves by editing constants and re-running arithmetic over stored JSON for free.

This document describes the **pipeline, the arithmetic, and the quality of the result**. The wording of the prompts themselves is out of scope — see `docs/ai-prompts.md`. For the design brief that motivated the current shape (what the score is *for*, and the two different jobs it does at the top and bottom of the list), see [`fit-scoring-problem-statement.md`](fit-scoring-problem-statement.md); for the constants as a tuning index, [`tuning.md`](tuning.md).

All distributions below were measured read-only against the live store on 2026-08-31: 1,591 jobs, 1,111 of them carrying a fit score, 1,878 successful `JobFitScore` rows across 5 résumés, 22,996 stored requirement assessments.

---

## 1. The pipeline, in order

### What triggers a score

Three entry points, all converging on `QueueActor.enqueueFitForActiveResumes`:

- **Automatically, after a successful extraction.** `core/LLM/QueueActor.swift:806-812` — every extracted job is scored against every *active* résumé as soon as its extraction commits. Duplicates are no longer exempted (TASK-624).
- **Manually**, via `JobService.rescoreFit(jobIDs:)` (`core/Services/JobService.swift:473`), which is what the Rescore command and the MCP `rescore_fit` route (`server/swift/MCPBridgeRoutes.swift:435`) call. This *discards the model's judgements and asks again* — the right thing after a prompt change, and the only path that costs money.
- **Résumé edits**, indirectly: `BackgroundStore.staleFitJobIDs(forResumeID:)` (`core/Services/BackgroundStore.swift:1083`) reports which scores were computed against text the résumé no longer has, so the user can choose to re-score them. Editing a résumé does **not** delete or recompute anything on its own; that used to happen and destroyed hundreds of scores at a keystroke (`core/Models/JobFitScore.swift:10-19`).

Enqueueing creates or reuses a `JobFitScore` row per (job, résumé) at `fitStatus = .pending`, clearing any stale `fitScore` on the reused row so the job's mirror doesn't keep showing the old number while a rescore is queued (`BackgroundStore.swift:1177`, TASK-519).

### What is fetched

`BackgroundStore.fitInputs(forJobID:resumeID:)` (`BackgroundStore.swift:1437`) builds the inputs on the store actor and hands back a `Sendable` snapshot — the live `Job` and `Resume` objects are never read off-actor (TASK-526).

**What the model is shown of the job is the extraction, not the posting.** `ExtractionEngine.buildJobContext` (`core/LLM/ExtractionEngine.swift:417`) parses `Job.extractedJSON` into title, company, seniority, summary, `requirements[]`, `nice_to_haves[]`, `skills[]`, and application instructions. The raw captured page (`Capture.cleanedDescription`) is never sent. This matters more than it looks: **every requirement the scorer can assess was decided by the earlier extraction call.** A requirement the extractor missed cannot be scored, and a requirement the extractor sliced badly is scored as sliced — see §6 on fragments.

What the model is shown of the candidate is the full `Resume.text` of one résumé. There is no skills inventory, no supplementary evidence block, and no user-correction text — corrections are applied deterministically in code and never appended to the prompt (`core/Services/ScoringFeedback.swift:9-13`).

### What comes back

One JSON response per call, requested with a strict `json_schema` response format (`ExtractionEngine.swift:298-303`, schema in `core/LLM/StructuredOutputSchemas.swift`), carrying:

- `dimensions[]` — five objects, each `{name, score 0–100, rationale}`.
- `requirement_assessments[]` — one object per requirement: `{requirement, kind ∈ {required, preferred}, status ∈ {met, partial, missing}, evidence}`. Median 12–13 per job (mean 12.7, max 66).
- `summary` — prose, displayed but not scored.
- Legacy `requirements_met` / `requirements_not_met` string arrays from the pre-Swift app, still read as a fallback.

`FitScorer.validateDimensions` (`core/Services/FitScorer.swift:370`) rejects the response outright if the five names aren't present exactly once each with numeric scores. That's deliberate: `computeScore` treats a missing dimension as 0, so a partial response would otherwise be stored as a plausible-looking low score instead of a retryable schema error (TASK-453).

### What is computed locally

Everything after the response. In `ExtractionEngine.scoreFit` (`ExtractionEngine.swift:274-373`), in order:

1. `EvidenceCheck.apply` marks assessments whose quoted evidence appears in neither the résumé nor the posting the model was shown (§6). **Marks only — no verdict changes.**
2. `FitScorer.requirementGaps` turns the assessments into a gap list, dropping non-discriminating requirements and fragments, and applying user corrections.
3. `FitScorer.requirementCounts` counts the requirements that survived the same filtering — the penalty's denominator.
4. `FitScorer.computeScore` does the arithmetic in §2.
5. `assessment_prompt_version` is stamped with the current constant (3), and the *checked* assessments are written back over the model's originals so the stored explanation matches the stored score.
6. `FitScorer.buildMergedJSON` overlays `overall`, `breakdown`, `penalty`, `penaltyReasons`, `scoreWeights` onto the raw model dict, so nothing the model said is lost.

### What is written where

`BackgroundStore.commitFitSuccess` (`BackgroundStore.swift:1569`) writes the score, the merged JSON, the model, `scoredAt`, and `resumeTextHash` onto the `JobFitScore` row; records an `LLMRequestAttempt` with token counts and the response format actually used; marks the `LLMRequest` succeeded; and recomputes the job's denormalized mirror — all inside one `saveAtomically()`.

### Model judgement vs deterministic code

| Produced by the model | Produced by Swift |
|---|---|
| The five dimension scores (0–100 each) | The weights, and the weighted average |
| Whether a requirement is `required` or `preferred` | The penalty grid, shrinkage, and normalisation |
| Whether it is `met` / `partial` / `missing` | Which requirements are dropped before scoring |
| The evidence quote and the rationale | Whether the quote is supported by the résumé text |
| The prose summary | User corrections, the mirror, and the stored version stamp |

Tuning the left column costs LLM calls and risks prompt dilution. Tuning the right column is free and reversible over the whole corpus.

---

## 2. The arithmetic, explicitly

### Dimensions and weights

`FitScorer.dimensionWeights` (`FitScorer.swift:64-70`) — must total 1.0:

| Dimension | Weight |
|---|---|
| `required_qualifications` | 0.40 |
| `preferred_qualifications` | 0.20 |
| `skills` | 0.15 |
| `domain_fit` | 0.15 |
| `experience_level` | 0.10 |

`preferred_qualifications` was raised and `experience_level` cut under TASK-602, on the observation that the model scores experience level near-constant (~98) so it was wasting discrimination at 0.20. That observation still holds — see §5.

### base

`FitScorer.baseScore` (`FitScorer.swift:407`):

```
base = round( Σ_d  clamp(round(dim_d), 0, 100) × w_d  /  Σ_d w_d )
```

Iteration is over `dimensionWeights.keys.sorted()` in **both** accumulations. Floating-point addition isn't associative and `Dictionary` order isn't stable, so an unordered sum could land either side of a rounding boundary — this produced a 70-vs-71 flake in CI, and a projection-layer reimplementation diverged on its first job because `Σ w = 1.0000000000000002` turned 89.5 into 89 (`FitScorer.swift:402-419`). A missing dimension contributes 0 rather than being skipped, so a partial response can't inflate the result.

### penalty — the normalised model (current)

Used whenever `requirement_assessments` are present, which is every score written since TASK-602. Constants at `FitScorer.swift:131-146`:

```
missWeight(missing) = 1.0        missWeight(partial) = 0.5
α = 2.0 (shrinkage)              prior = 0.184

fraction(misses, total) = (misses + α × prior) / (total + α)

penalty = round( 65 × fraction(requiredMisses,  requiredTotal)
               + 12 × fraction(preferredMisses, preferredTotal) )
```

`requiredTotal` / `preferredTotal` count only the requirements that survived filtering, and the numerator is built from the same filtered set — if the two disagreed, dropping a requirement would perversely *raise* the penalty (`FitScorer.swift:156-158`).

Bounded by construction at **77** (65 + 12), so no score sits in a flat region where further gaps change nothing. Two properties worth naming:

- **The shrinkage taxes perfect matches.** With zero misses, `fraction = 0.368/(total+2)`, which is never zero. A job with 6 required and 4 preferred requirements, all met, still loses 4 points. That is intentional — a terse posting gave the model less to find fault with, and shouldn't score as confidently as a detailed one — and α was fitted at 2 against a 412-job corpus rather than inherited (`FitScorer.swift:136-144`).
- **Preferred gaps are now nearly harmless.** At 12 points of headroom against required's 65, missing *every* preferred qualification on a 5-preferred posting costs about 10 points. This is the fix for the saturation described in §3 of the problem statement.

### penalty — the legacy additive model

Only for rows that stored `requirements_not_met` strings and no structured assessments (`FitScorer.swift:460-469`). No denominator exists, so it sums a fixed grid — required/missing −12, required/partial −6, preferred/missing −10, preferred/partial −5 — and caps at `penaltyCap = 60`. This is the model whose failures motivated the rewrite; it survives only so old rows recompute to *something* rather than nil.

### score

```
score = max(0, base − penalty)
```

### `penaltyReasons`

Under the normalised model, one string per gap: `"<requirement> (<kind>/<status>)"` — no per-item point value, because under normalisation a gap has no fixed cost. Under the legacy model the cost is appended. `buildMergedJSON` copies these into `requirements_not_met` when that key is absent, which is what the read model and the exporter expect.

### Worked example — job #1524 (PlayStation, Senior PM Monetization)

Stored breakdown: `required 95, preferred 95, skills 90, domain_fit 90, experience_level 95`. Assessments: 6 required, 4 preferred, **all `met`**, no user corrections, nothing filtered.

```
base = 0.40×95 + 0.20×95 + 0.15×90 + 0.15×90 + 0.10×95
     = 38 + 19 + 13.5 + 13.5 + 9.5  =  93.5  → 94

requiredMisses = 0,  requiredTotal = 6
  fraction = (0 + 2×0.184)/(6+2) = 0.368/8 = 0.0460 → ×65 = 2.99
preferredMisses = 0, preferredTotal = 4
  fraction = 0.368/6 = 0.0613            → ×12 = 0.736
penalty = round(3.726) = 4

score = 94 − 4 = 90
```

Stored: `overall 90`, `penalty 4`, `penaltyReasons []`. A flawless match loses 4 points to the shrinkage alone; that is the arithmetic working as designed, but it is also why nothing in this corpus reaches 100 by merit.

### Worked example — job #1502

Stored breakdown: `required 95, preferred 100, skills 95, domain_fit 60, experience_level 90`. Assessments: 10 required (9 `met`, 1 `partial`), 6 preferred (all `met`).

```
base = 0.40×95 + 0.20×100 + 0.15×95 + 0.15×60 + 0.10×90
     = 38 + 20 + 14.25 + 9 + 9  =  90.25  → 90

requiredMisses = 0.5 (one partial), requiredTotal = 10
  fraction = (0.5 + 0.368)/12 = 0.0723   → ×65 = 4.70
preferredMisses = 0, preferredTotal = 6
  fraction = 0.368/8 = 0.0460            → ×12 = 0.55
penalty = round(5.25) = 5

score = 90 − 5 = 85
```

Stored: `overall 85`, `penalty 5`, one reason — *"Ability and willingness to travel periodically (approximately 10–15% annually) for team meetings and company events (required/partial)"*. Note what that reason is: a requirement satisfiable by disposition, of exactly the family `isNonDiscriminating` exists to drop, which its keyword list doesn't cover. It cost 4 points, and `domain_fit = 60` cost 6 — the single largest contributor to this job's shortfall is a dimension no requirement bullet ever stated.

---

## 3. Multi-résumé handling

One `JobFitScore` row per (job, résumé) pair — `core/Models/JobFitScore.swift`. A job with four active résumés gets four LLM calls and four independent scores.

Currently in the store: **1,878 successful scores across 5 résumés for 1,260 jobs.** 1,070 jobs carry one score, 187 carry four or five, 3 carry two or three. Only one résumé (`Brooks_Cutter_Resume_Master`, 44,920 chars) is `active`; the four tailored résumés (≈5.6–6.0k chars each) are shelved, holding 769 scores between them.

### The mirror

`Job.fitScore` / `Job.fitStatus` / `Job.fitScoreJSON` are a denormalized copy, computed by `BackgroundStore.computedFitMirror(for:)` (`BackgroundStore.swift:600-619`):

- **Best score across ACTIVE résumés only.** A deactivated résumé is one the user has stopped applying with, so its score no longer describes their fit. Scores are kept, not deleted — reactivating restores them.
- Falls back to `.running` → `.pending` → `.failed` → `.none` when no active résumé has a number yet.
- Orphaned rows (no `resume` relationship — legacy migration artifacts) never drive the number.

Consequence visible in the store right now: **1,260 jobs hold a score but only 1,111 have a mirror.** The ~149 difference is jobs scored solely against the four shelved résumés — they read as unscored throughout the app while their analyses sit in the database.

The mirror is what the Jobs list ring, sorting, the `min_fit_score` filter (`JobRequirements.evaluate`, `core/Services/JobRequirements.swift:140-151`), the Dashboard, and MCP all read. The detail view is the exception: `FitAnalysisProjection` (`core/Models/Projections.swift:146-198`) recomputes the number at read time with user corrections applied, so the ring and the requirement rows can't disagree.

### When it goes stale

The mirror is recomputed on every write path that could move it — save, pending, running, failed, orphan reconciliation, recompute. It drifts anyway, from:

- **Migration.** Rows carried over by the one-time import from the pre-rewrite SQLite database (a historical event, not an ongoing path), or scores deleted without a recompute.
- **Résumé activation changes.** Toggling `Resume.active` changes what the mirror should be, and nothing recomputes the whole corpus at that moment.
- **Crashes between the score write and the save.**

`--recompute-fit-mirrors` (`tools/migrator/Args.swift:14`, → `BackgroundStore.recomputeAllJobFitMirrors`, `BackgroundStore.swift:636`) exists for exactly this. It compares each job's stored mirror to the recomputed one and writes only where they differ, so it doesn't bump `updatedAt` across the whole library. Run with the app quit.

Distinguish it from the two neighbours it is easy to confuse:

| Operation | Cost | What it does |
|---|---|---|
| `--recompute-fit-mirrors` | free | Fixes `Job.fitScore` from existing `JobFitScore` rows. No score changes. |
| `recomputeAllFitScores` (in-app, Debug tab) | free | Re-runs the *arithmetic* over every stored analysis with current weights + current corrections. Model judgements unchanged. |
| `JobService.rescoreFit` | LLM calls | Throws away the judgements and asks the model again. Required after a prompt change. |

### Résumé versioning

`JobFitScore.resumeTextHash` records the fingerprint of the text that produced the score. `reflectsPreviousResumeVersion` (`JobFitScore.swift:50`) is true when it differs from the résumé's current text; nil means the row predates the field and is treated as *unknown*, not stale.

In the store: **969 of 1,878 rows have no hash at all** (all 769 rows against the four shelved résumés, plus 266 of the master's). Of the master résumé's 846 hashed rows, 820 are on one text version and **26 on another** — those 26 are scores against a résumé revision that no longer exists.

---

## 4. Versioning and comparability

`FitScorer.assessmentPromptVersion` (`FitScorer.swift:211`) is stamped into every live score and preserved verbatim by recompute (`buildMergedJSON`, `FitScorer.swift:562-566`) — a recompute re-runs arithmetic over old judgements and must not relabel them as new.

- **v1** — original.
- **v2** — named technologies require literal evidence to score `met`.
- **v3** — a menu of alternatives is judged against the option the posting emphasises; `domain_fit` means industry and product, not transferable craft.

**Current composition of the corpus.** Of the 1,111 job mirrors: **872 are v3 (78%), 12 are v2, 227 are v1 (20%)**. Across all 1,881 `JobFitScore` rows the picture is worse — 872 v3, 12 v2, 994 v1 — because the v1 population is concentrated in the shelved-résumé scores.

**Three axes make two scores incomparable, and only one is repairable for free:**

1. **Prompt version.** v1 and v3 are different measurements of different things. Recomputing cannot reconcile them — the arithmetic is identical, it is the model's judgement that moved. Fixing this costs 227 LLM calls.
2. **Arithmetic version.** Not stamped anywhere. `scoreWeights` is stored per score, which records the weights but not the penalty model. Recompute makes this moot: it brings every row onto today's arithmetic at zero cost, and should be run after any change to `FitScorer`.
3. **Résumé revision.** Tracked by `resumeTextHash`, unknown for 969 rows.

Practical reading: **a `min_fit_score` filter or a sort over the whole library today is mixing two prompt populations at roughly 4:1.** The v1 fifth was assessed under rules that credited adjacent experience much more freely, so those 227 jobs sit systematically high relative to their v3 neighbours. Re-scoring them is the cheapest thing on the improvement list that isn't free.

---

## 5. Real distributions

All figures from the live store, 2026-08-31. "Corpus" means the 1,111 jobs with a mirror unless stated; per-dimension figures are restricted to the 872 v3 mirrors so two prompt populations aren't averaged together.

### Coverage

| | Count |
|---|---|
| Jobs in library | 1,591 |
| With a fit score (mirror) | 1,111 (70%) |
| `fitStatus = none` | 479 |
| `fitStatus = failed` | 1 |
| Stored `JobFitScore` rows (succeeded) | 1,878 |
| Requirement assessments stored | 22,996 |

### Score histogram

| Band | Jobs | Share |
|---|---|---|
| 0–9 | 91 | 8.2% |
| 10–19 | 65 | 5.9% |
| 20–29 | 96 | 8.6% |
| 30–39 | 115 | 10.4% |
| 40–49 | 114 | 10.3% |
| 50–59 | 134 | 12.1% |
| 60–69 | 121 | 10.9% |
| 70–79 | 144 | 13.0% |
| 80–89 | 117 | 10.5% |
| 90–100 | 114 | 10.3% |

Mean 53.0, median 54, full 0–100 range used.

**Read this histogram as two populations, not one.** It blends every rubric version the store holds, and the versions disagree by a lot (TASK-711, measured the same day):

| version | n | mean | median | p25 | p75 |
|---|---|---|---|---|---|
| v1 | 977 | 68.9 | 74.0 | 56 | 89 |
| v2 | 12 | 94.7 | 96.0 | 94 | 97 |
| v3 | 823 | 50.0 | 50.0 | 31 | 70 |

(Counted over job mirrors. Recounting instead over all 1,878 succeeded `JobFitScore` rows gives 994 v1 at mean 67.7, 12 v2 at 94.7, 872 v3 at 47.2, and 3 rows with no version at all — a wider gap on a wider base, same conclusion.)

A 19-point mean gap, with v1 still 54% of the corpus. So the corpus-wide flatness is partly an artifact of laying a generous rubric over a harsh one, and the mean of 53 is not a property of the *current* scorer at all — it is the average of two incomparable measurements. **The corpus-wide figures above cannot support a calibration claim.**

**The current rubric does discriminate, though — v3 alone is well spread**: median 50, quartiles 31 and 70, across the full range. Judged on v3 only, this is a large improvement on the distribution the problem statement recorded on 2026-08-02 (14% under 10, 25% at 90+, hollow middle, median 66): the normalised penalty removed the U-shape, cap occupancy is zero (the legacy 60-cap no longer fires on any row), and the zero pile is down from 14% to 8.2%.

Rubric version is now a queryable column (`JobFitScore.assessmentPromptVersion`), so this split can be measured rather than reconstructed: `JobhuntMigrator --fit-version-histogram` reports it, and `--rescore-stale-fit-scores` clears the older populations.

### Penalty spread

| Penalty | Jobs |
|---|---|
| 0 | 8 |
| 1–9 | 392 |
| 10–19 | 379 |
| 20–29 | 220 |
| 30–39 | 87 |
| 40–49 | 21 |
| 50–59 | 4 |

Mean 15.1, max 55 against a construction bound of 77. Nothing is pinned. Only 8 jobs score a zero penalty, which is the shrinkage: a perfect match still pays.

### Base

Recovered as `score + penalty` for the 1,103 jobs scoring above 0 (the floor destroys the base for the other 8):

| Base | Jobs |
|---|---|
| <50 | 174 |
| 50–59 | 174 |
| 60–69 | 187 |
| 70–79 | 169 |
| 80–89 | 181 |
| 90–100 | 177 |

Strikingly uniform, and much less generous than the "median 84" the problem statement recorded — the v3 prompt tightened the dimensions themselves, not only the penalty. **The base, not the penalty, is now doing most of the separating.** Mean penalty is 15 against a base spread covering the full range.

### Per-dimension behaviour (v3 only, n=872)

| Dimension | Mean | Mean weighted shortfall (of 100) |
|---|---|---|
| `required_qualifications` | 73.0 | 10.8 |
| `preferred_qualifications` | 50.5 | 9.9 |
| `domain_fit` | 33.8 | 9.9 |
| `skills` | 63.8 | 5.4 |
| `experience_level` | 90.1 | 1.0 |

Which dimension is the largest weighted shortfall — i.e. the one limiting the score:

| Limiting dimension | Jobs |
|---|---|
| `required_qualifications` | 382 (44%) |
| `domain_fit` | 251 (29%) |
| `preferred_qualifications` | 235 (27%) |
| `skills` | 2 |
| `experience_level` | 2 |

Two facts follow immediately.

**`experience_level` is inert.** 76% of jobs score it 90–100; it is the limiting dimension on 2 jobs out of 872 and contributes an average shortfall of 1.0 point out of 100. It occupies 10% of the weight budget and carries essentially no information. This was already noted in TASK-602 and the weight was cut from 0.20 to 0.10; the observation is that the cut did not go far enough.

**`domain_fit` is the second-largest force in the score**, at a mean of 33.8 — by far the harshest dimension. This is a direct consequence of the v3 rule that `domain_fit` means the industry and product rather than transferable craft.

### Requirement verdicts (v3, 11,106 assessments)

| | met | partial | missing |
|---|---|---|---|
| **required** | 5,406 | 1,387 | 720 |
| **preferred** | 1,244 | 915 | 1,434 |

Required qualifications are credited 72% of the time; preferred only 35%. The model is markedly stricter about nice-to-haves than must-haves, which is the opposite of what a human screener does and is worth interrogating (§7).

### Does the score match what the user does?

| Status | Jobs | Mean score |
|---|---|---|
| rejected | 14 | 93.8 |
| interview | 2 | 94.0 |
| applied | 26 | 88.3 |
| pursuing | 24 | 76.7 |
| new | 175 | 69.5 |
| expired | 86 | 65.6 |
| archived | 751 | 44.2 |

Crossed against the bands:

| | archived | applied | pursuing | new |
|---|---|---|---|---|
| 80+ | 95 | 24 | 12 | 36 |
| 50–79 | 203 | 1 | 11 | 139 |
| <50 | 453 | 1 | 1 | 0 |

**This is the strongest evidence in the store that the score works.** 24 of 26 applications and 12 of 24 actively-pursued jobs sit at 80+; exactly two of the 51 acted-on jobs came from below 50, against 453 archived. The score separates what the user acts on from what they discard, and it does so with almost no error at the bottom — the low end is a reliable filter.

The top is weaker. 95 archived jobs score 80+ — a third of the 80+ population — so a high score is far from sufficient. `rejected` scoring highest of all (93.8) is not a scoring failure: those are jobs the user applied to and an employer declined, so they are drawn from the same high-scoring pool as `applied`.

Discrimination by missing-required count is clean:

| | Jobs | Mean score |
|---|---|---|
| Zero required qualifications missing | 483 | 63.8 |
| One or more missing | 386 | 26.5 |

A 37-point gap. The problem statement's criterion "jobs with a missing required qualification separate cleanly from those without" is met.

### Where it does not discriminate: the top of the list

- **177 jobs (16% of the corpus) score 85 or above** — the `FitBand.strong` threshold (`core/Services/FitBand.swift:17`).
- The **top 50 jobs span only 7 distinct score values**. Seven jobs per point, at the exact end of the list where the score is supposed to allocate an evening of work.
- The single most common score in the 85+ range is 89, with 22 jobs on it.

The problem statement names this precisely: "ties are the enemy — a scheme that puts half the corpus at 90+ has no top to rank". It is no longer half the corpus, but the top 50 is still effectively unranked.

### Where it does not discriminate: the zero-missing-required floor failures

The problem statement's §8 criterion "no job missing zero required qualifications scores below the user's threshold on preferred-qualification gaps alone" is **not met.** Of 483 v3 jobs missing no required qualification, **110 (23%) score below the user's configured `min_fit_score` of 50**, and are therefore filtered out of the Jobs list by default.

But the cause has changed. Those 110 average base 57.1 and penalty 17.8 — the penalty is no longer the culprit, since a bounded 12-point preferred term cannot push a job under 50 on its own. Their averages against the zero-missing population as a whole:

| | n | base | penalty | domain_fit | required | preferred |
|---|---|---|---|---|---|---|
| Zero missing required, score <50 | 110 | 57.1 | 17.8 | **26.3** | 72.6 | **33.3** |
| Zero missing required, all | 483 | 74.2 | 10.4 | 44.4 | 86.4 | 61.6 |
| Has a missing required | 386 | 51.0 | 24.5 | 20.5 | 56.6 | 36.7 |

The 110 fail on `domain_fit` (26.3) and `preferred_qualifications` (33.3) **in the base**, not through the penalty. Note that their `required_qualifications` dimension is 72.6 despite the model marking zero required requirements missing — the dimension and the verdicts disagree here in a way they don't corpus-wide, driven by the `partial` verdicts (which appear on 18% of required requirements).

---

## 6. The evidence check

`core/Services/EvidenceCheck.swift`. The scoring prompt asks the model to quote its evidence. The check tests, deterministically, whether the quote is actually in the résumé.

### How it works

1. `quotedSpans` (`EvidenceCheck.swift:68`) extracts 5–120 character spans between matched quote marks, with a regex that refuses to open or close mid-word — otherwise `don't` and `it's` read as quotes, which was most of the false positives on the first pass. Spans containing an ellipsis are skipped: the model is signalling that it abbreviated.
2. `normalized` folds curly quotes, dashes, whitespace and case.
3. `classify` does a **substring** lookup of each normalised span in (a) every résumé text supplied and (b) the posting text the model was shown, yielding `supported` / `liftedFromPosting` / `invented`.
4. `apply` marks an assessment only when it has at least one span and **none** of them is supported. A single supported quote clears the whole assessment; an assessment quoting nothing is left alone. The outcome is written into the stored JSON as `evidence_support` and `unsupported_evidence`, so the UI can show *which* words aren't in the résumé.

On the live path, the haystack is `ExtractedJobContext.quotableText` (`core/LLM/PromptBuilder.swift:373`) — the concatenation of exactly what was in the prompt. Checking against the raw capture would accuse the model of copying text it never saw.

### What it can detect

The failure it was built for, which is real and measured in the code's own comments (`EvidenceCheck.swift:5-15`): 32% of quoted spans corpus-wide appear in no résumé the user has ever had, across 44 of 415 jobs, and **74% of those are lifted verbatim from the job posting**. The mechanism is legible — the prompt demands a literal named technology, the résumé has none, the nearest literal string is in the JD, so the model copies it and presents it as résumé content. The remaining quarter is invention, including job #200 quoting `Certification: Project Management Professional (PMP).` as résumé text.

### What it cannot detect, and the rule that was removed

**A substring test cannot tell invention from paraphrase, and paraphrase is far commoner.** An earlier version demoted a credited verdict to `missing` when its quotes appeared in neither document. Checked against the 20 hand-labelled jobs, that rule fired 7 times and **6 of the 7 contradicted the labeller**, who had marked all six `met` (`EvidenceCheck.swift:126-142`). The requirements it hit were "Builder mentality", "Excellent communication", "Strong product sense" — where the evidence was real résumé content lightly reworded or reassembled across lines.

So the check **surfaces, and never decides**. `recheckStoredEvidence` (`BackgroundStore.swift:819`) explicitly moves no score and recomputes no mirror.

It also cannot see anything at all for the 81% of assessments whose evidence contains no quotation marks (4,253 of 22,996 assessments quote anything). Silence is not treated as guilt — deliberately, since that would penalise models that abstain rather than invent — but it does mean the check's coverage is a fifth of the corpus.

### `--recheck-evidence`

`tools/migrator/Args.swift:14`. Runs `recheckStoredEvidence` over every succeeded `JobFitScore`, skipping rows where the résumé text or the capture's `cleanedDescription` is missing (without both documents the check can't distinguish "unsupported" from "the text isn't here to search"). Idempotent. Run with the app quit.

**Its results are barely present in the current store: 59 rows carry any mark, totalling 88 `invented` and 40 `liftedFromPosting` assessments out of 22,996.** That is far below the 32%-of-quoted-spans figure the code records, which means either the pass has not been run since most of the corpus was scored, or most rows are being skipped for want of a stored `cleanedDescription`. I could not distinguish these without running the migrator, which is out of scope here. **Worth checking before drawing any conclusion from the low flag count** — as it stands, the absence of marks is not evidence of clean evidence.

Note also that `recheckStoredEvidence` (`BackgroundStore.swift:830`) checks against `job.capture?.cleanedDescription`, whereas the live path checks against `quotableText`. The offline pass therefore uses a *larger* haystack than the model actually saw, so it will classify some genuine inventions as `liftedFromPosting` — a milder label than warranted. Not a bug in effect, since nothing acts on the distinction, but the two paths do not agree.

### How "I don't have this" flows back

`ScoringFeedback` (`core/Services/ScoringFeedback.swift`) — four kinds, captured by flagging a requirement in the detail view:

| Kind | Effect | Polarity |
|---|---|---|
| `alwaysCredit` ("I do have this") | Scores `met`, no penalty | credits |
| `neverCredit` ("I don't have this") | Scores `missing`, **is** penalised | penalises |
| `notARequirement` | Dropped entirely, hidden | neutral |
| `jobSpecific` | Dropped, for that job only | neutral |

Matching is `ScoringFeedback.matches(phrase:in:)` — **whole-word**, after a production incident where the three-character phrase `IDE` matched *provide*, *identify*, *ideally* and force-credited 359 requirements across 124 of 415 jobs, inflating 28 scores by up to 34 points (`ScoringFeedback.swift:143-146`). `FeedbackMatchPreview` now measures a candidate rule's blast radius before it can be saved, flagging anything reaching more than 10% of jobs.

Feedback is applied in four places that must agree exactly: gap construction, the penalty denominator, the verdict share, and the read-model projection (`FitScorer.swift:291-296`).

**The current rule set does not generalize.** All 9 stored rules are `alwaysCredit`, and every one of them is a full requirement sentence copied verbatim from the job it was flagged on ("Demonstrated experience with generative AI platforms", "Must be eligible to maintain security clearance", "proficiency in Google Sheets"). Each matches exactly the one requirement it came from, out of 22,996. The mechanism works; it is being used as a per-job override rather than as a correction that generalises, which is what the whole-word matching was tightened to permit.

**Corrections are applied when a score is first computed (fixed, TASK-707).** They weren't: `scoreFit`'s `feedback:` parameter was defaulted and `QueueActor` — the path every automatically queued score goes through — omitted it, so a freshly scored job's stored `fitScore` and its mirror ignored every correction until someone ran `recomputeAllFitScores`. The detail view hid it, because `FitAnalysisProjection` recomputes with feedback at read time (`Projections.swift:196-198`), while the Jobs list ring, the sort and the `min_fit_score` filter all read the uncorrected mirror. The queue now reads the corrections through an injected closure (`readScoringFeedback`, matching `readExtractionSettings`) and passes them with the job number, and `scoreFit` no longer defaults the parameter — a caller with nothing to apply passes `[]` and says so, so the next omission is a compile error rather than a silent empty list.

**Adding a correction does not require re-scoring what is already scored.** Corrections are applied deterministically over the stored assessments, so `recomputeAllFitScores` (free, offline, no LLM calls) propagates a new rule to every existing score. New jobs get it on the live path; old jobs get it from a recompute. Nothing here needs to spend an LLM call, and no automatic bulk re-score fires when a correction is added.

---

## 7. Where this could be improved

Ranked by expected benefit. Everything here is grounded in §5; the machinery to test any of it already exists and is free — `ScoringVariant` + the `ScoreLab` CLI (`core/Services/ScoringVariant.swift`, `tools/scorelab/main.swift`) score through the same `FitScorer` code the app uses, over the live store, with no LLM calls. There is no excuse for shipping any of these unmeasured.

### 1. Break the ties at the top — the score's primary job is the one it does worst

The top 50 jobs occupy 7 distinct values; 177 jobs share the 16 values from 85 to 100. Everything else in §5 says the score is healthy: full-range distribution, no saturation, a 37-point gap on missing-required, applications concentrated at 80+. The one thing it cannot do is the thing the problem statement calls the *primary* criterion — rank the top so the user knows which evening to spend.

The compression is structural, not accidental. `base` is a weighted average of five 0–100 numbers, and averages of five numbers that are all high are all high; the penalty adds at most 77 but averages 15 and cannot separate jobs that have no gaps. Three things to measure, cheapest first:

- **Re-score only the 85+ band and look at run-to-run variance first.** `ScoringVariant.current`'s own doc comment records that on identical input the dimension numbers alone moved the base 26 points. If the noise floor at the top is ±10, no re-weighting will produce a trustworthy ranking and the honest fix is to stop presenting the top as ordered at all — show the band and the missing-required count, and let the user choose. **Do this measurement before any of the others**; it determines whether the rest is worth doing.
- **Test `.hybrid`.** It already exists (`ScoringVariant.swift:36`), blending the requirement-verdict share with only `domain_fit` and `experience_level`. It removes three of the five variance sources. `ScoreLab` compares it against `.current` over the whole corpus in seconds; that comparison has apparently not been recorded anywhere, and it should be.
- **Widen the top deliberately.** Nothing scores 100 by merit because the shrinkage taxes a perfect match 3–4 points. If the top band is to be rankable, α could be applied only where there *are* misses, restoring the full 94–100 range to jobs that genuinely have no gaps. This is a two-line change to `penaltyFraction` and costs nothing to evaluate.

**Expected benefit: high.** This is the score's stated primary purpose and its clearest measured failure.

### 2. Reallocate the weight `experience_level` is wasting, and interrogate `domain_fit`

`experience_level` averages 90.1, is the limiting dimension on 2 of 872 jobs, and contributes 1.0 point of average shortfall for 10% of the weight budget. It is a constant with jitter. TASK-602 cut it from 0.20 to 0.10 for exactly this reason and the diagnosis was right but the dose was too small.

`domain_fit`, meanwhile, averages 33.8 and is the limiting dimension on 29% of jobs — the second-largest force in the score. The brief asks whether it is penalising career changes the user is fine with. **The store says no, and this is worth stating clearly because it contradicts the intuition:**

| Status | Mean `domain_fit` |
|---|---|
| applied | 76.4 |
| pursuing | 53.8 |
| new | 46.8 |
| archived | 28.2 |

`domain_fit` tracks the user's own behaviour more sharply than the overall score does. The jobs they actually apply to are the ones with domain overlap. It is earning its 0.15 and arguably more.

So the experiment is: move weight from `experience_level` to `domain_fit` (or to `required_qualifications`), re-score over the corpus, and check whether the 80+ band spreads. Free, reversible, and the `scoreWeights` field stored on every score means the change is auditable after the fact. Note that if `experience_level` is dropped below about 0.05 it should probably be removed from `dimensionWeights` entirely rather than kept as a token — but that changes `validateDimensions`' contract and forces a prompt-version bump, so it is not free.

**Expected benefit: medium-high.** Cheap to test, directly addresses the compression in #1, and rests on a clean measurement.

### 3. ~~Pass user corrections on the live scoring path~~ — done (TASK-707)

`QueueActor` didn't pass `feedback:` or `jobNumber:` to `scoreFit`, so every newly scored job's stored number and mirror ignored all 9 corrections until a manual recompute — sorting, the `min_fit_score` filter and the Jobs-list ring running on uncorrected numbers while the detail view showed corrected ones. Fixed as described in §6: the queue reads the corrections through an injected closure and passes them, and the parameter's default is gone so the omission can't recur silently. The effect was small at the time (all 9 rules were single-requirement `alwaysCredit` entries) and grows with any correction that generalises, which is the mechanism's design intent.

### Also worth doing, but lower

- **Re-score the 227 v1 jobs.** A fifth of the library is a different measurement, assessed under rules that credited adjacent experience far more freely, and it is being sorted and filtered alongside v3 scores as if comparable. Costs 227 LLM calls at gemini-3.7-flash rates — cheap in absolute terms. Nothing else on this list is confounded by it, since the per-dimension analysis above is v3-only, but the user's own list is.
- **Verify `--recheck-evidence` has actually run.** 59 marked rows against a documented 32%-of-quoted-spans failure rate does not add up. Either the pass is stale or most rows are being skipped for a missing `cleanedDescription`. Until that is resolved, the absence of evidence flags means nothing, and the UI is quietly reassuring the user.
- **Ask why preferred qualifications are credited at 35% against required's 72%.** The model is stricter about nice-to-haves than must-haves, which inverts what a human screener does and directly depresses the `preferred_qualifications` dimension (mean 50.5, 27% of jobs' limiting factor). Some of this is the fragment problem — `FitScorer.isFragment`'s doc comment records that 34.9% of *preferred* requirements corpus-wide are contentless noun phrases the extractor sliced out of a list, against 1.8% of required. The deterministic filter drops them from scoring, but the model still saw them when it produced the `preferred_qualifications` dimension number, so the dimension is depressed by fragments the penalty correctly ignores. **Fixing this belongs in the extractor, not the scorer** — and it may be the single cheapest structural improvement available, since it improves the input to both calls.
- **Cheaper models.** Not assessed here — the store records `model` per score but comparing quality across models needs the eval harness (`tests/LLMEval/`) and real API calls. The benchmark that selected `google/gemini-3.7-flash` (`docs/model-benchmark-2026-08.md`) found it tied `openai/gpt-5.6-sol` at 6× lower cost with zero verdict flips across 5 runs, and found `gemini-3.1-flash-lite` failing the over-credit fixture 5 times in 5. **There is no evidence a cheaper model would score equivalently, and some that the next tier down does not.** Given that dimension noise is already the largest source of variance, moving down a tier would likely make #1 worse.

### What I could not determine without running the app or spending API budget

- Whether `--recheck-evidence` is stale or being skipped (needs a migrator run).
- Run-to-run variance of the current scorer on this corpus (needs LLM calls).
- How `.hybrid` and `.verdictShare` actually compare against `.current` here (needs a `ScoreLab` build — the code exists, the numbers do not).
- Whether the 110 zero-missing-required jobs scoring under 50 are correctly scored. That is a ground-truth question, and per the problem statement's §6 it can only be answered on the résumé side.
