# Tuning & heuristic constants

Most constants in the codebase are technical (ports, byte limits, retry counts) and live next to the
code that uses them — leave those alone. This doc indexes the **opinionated / heuristic** constants:
the ones that encode a judgment call, get iterated on, or that you might want to tweak as the job
market, sites, or your own preferences change. Each lives as a named `static let` (or a small helper)
so it's greppable and changeable in one place.

> Not a config system — these are code constants. Changing them needs a rebuild. Where a knob is
> genuinely per-user it's a **Setting** instead (see the last section).

## Fit scoring — `core/Services/FitScorer.swift`

The most-iterated heuristics. See [job-detail-pane-spec.md](job-detail-pane-spec.md) and the fit
section of the code for the full algorithm.

| Constant | Meaning |
|---|---|
| `dimensionWeights` | Per-dimension weights (must total 1.0). Currently required .40, preferred .20, skills .15, domain_fit .15, experience_level .10. |
| `penaltyPoints(kind:status:)` | The gap-penalty grid: required/missing −12, required/partial −6, preferred/missing −10, preferred/partial −5. |
| `penaltyCap` | Max total penalty (60). |

The LLM supplies the raw per-dimension scores and per-requirement `kind`/`status`; this file turns
them into the final number. To retune: edit the weights and/or the grid, rebuild, then **re-run AI
scoring** (or `recomputeAllFitScores` for a no-LLM reweight of existing rows). Candidate for a future
user setting — preference genuinely varies by person and market.

## Duplicate detection — `core/Services/DuplicateDetector.swift`

- **Confidence formula constants** (the `MARK: - Tuning constants` block): `baseDomainConfidence`,
  `rankSpreadWeight`, `descFullWeightTokens`, `descAdjustmentScale`, `descSimilarityMidpoint`,
  `fieldConflictPenalty`, `confidenceFloor`/`confidenceCeiling`, `salaryDivergenceThreshold`,
  `companyClusterThreshold`. These were inline magic numbers; named so the formula in
  `duplicateGroups` is legible and adjustable in one spot.
- **Word lists** (extend as noise surfaces): `companyStopWords`, `descriptionStopWords`,
  `atsRegistrables` (known ATS domains).

## Availability / "posting is gone" — `core/Services/AvailabilityChecker.swift`

Expect to keep extending these as new sites and wording appear:
- `goneStatusCodes` — HTTP codes that mean gone (404/410).
- `goneBodyPatterns` — literal removal phrases; add new ones here.
- `goneBodyRegexes` — generalized removal-phrase families (anchored to a job-subject noun to avoid
  false positives).
- ATS "not found" landings — `isBoardErrorLandingURL` (Greenhouse `?error=true`, Workable `/oops`) and
  `isLinkedInClosedJob`. Add a new ATS as a host-scoped, deterministic rule.
- `timeoutSeconds`, `userAgent`.

## Outbound job-search links — `core/Services/JobSearchLinks.swift`

The detail pane's "Find a referral" (LinkedIn) and "Find on company site" (Google) buttons.

- `excludedAggregatorDomains` — job boards pushed *out* of the "find on company site" Google results
  (`-site:` exclusions). ATS domains (greenhouse/lever/workday) are deliberately kept — applying via a
  company's ATS is "direct." The query itself (`{company} {title} (careers OR jobs) -site:…`) lives in
  `companySiteSearchURL`; tweak there.
- `genericCompanyTokens` — company-name words too generic to prove a URL belongs to the company
  (used by `postingIsOnCompanySite`, which disables the button when the posting is already on the
  company's site/ATS). Deliberately loose substring matching — accepts occasional false positives.

## Data quality — `core/Models/QualityIssue.swift`

- `staleThresholdDays` (21) — an *extraction* is old enough to re-run. **Intentionally separate** from
  the `availability_stale_days` setting (which is about re-checking whether the *posting* is live).
  Same number, different question — don't couple them.
- `minRawBytes` / `minCleanedBytes` — thin-content thresholds.

## Already user-configurable (Settings, not code)

These are surfaced in **Settings** and stored per-user (`SettingsStore` defaults) — tweak in the app,
not here: `availability_stale_days`, `availability_auto_check_interval_days`,
`availability_auto_check_enabled`, location/remote filters, LLM provider/model/pricing, OpenRouter
free-model rotation.

## Adding a new heuristic constant

1. Give it a named `static let` next to related ones (not an inline literal).
2. Add a one-line doc comment.
3. Add it to the relevant section above.
4. If it's a per-user preference rather than a global default, make it a **Setting** instead.
