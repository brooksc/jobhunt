# Test Database Specification

## Problem Statement

Jobhunt currently has three data sources for tests:

| Source | Used by | Problem |
|---|---|---|
| Production DB (`~/Library/Application Support/Jobhunt/`) | Never (blocked by `--ui-test-store`) | Personal data — must never be touched by tests |
| In-memory store | CoreTests, ServerTests | Ephemeral, seeded programmatically via `DemoSeeder`; limited permutations |
| DemoSeeder (in-memory) | AppUITests (`--seed-demo-data`) | Designed for demos, not test coverage; no expired/removed JDs, limited status variety, not real job descriptions |

The gap: there is no durable, version-controlled, comprehensive test fixture database that covers the full range of application states. This means tests that depend on real-world data variety (expiration, quality issues, duplicate detection, archive eligibility, LLM extraction edge cases) can't be written reliably.

## Proposed Solution

A **golden SQLite fixture database** checked into git at `tests/fixtures/jobhunt-test.sqlite`, copied fresh into a temp location at the start of each test run. Tests read and write against the copy; the original is never mutated by tests.

---

## Fixture Database Design

### How it's used

**AppUITests**: Launch arg `--fixture-db tests/fixtures/jobhunt-test.sqlite` tells the app to copy the fixture to a temp path and open that copy. Replaces `--seed-demo-data` for tests that need real data variety.

**CoreTests / ServerTests**: `ModelContainerFactory.fixture()` opens the copied fixture. Existing `ModelContainerFactory.inMemory()` remains for tests that don't need the fixture.

**Isolation guarantee**: The fixture file itself is read-only in tests (opened via a copy). Each test class that needs isolation gets its own copy via a per-class setup helper.

### Seeding workflow

The fixture is built manually and committed:
```bash
# One-time: generate the fixture
./scripts/seed-test-db.sh

# After changes to the fixture schema or content:
./scripts/seed-test-db.sh --rebuild

# Commit the result
git add tests/fixtures/jobhunt-test.sqlite
git commit -m "Update test fixture database"
```

`seed-test-db.sh` runs a special app build with `--seed-fixture` that calls a `FixtureSeeder` (separate from `DemoSeeder`) and writes to `tests/fixtures/jobhunt-test.sqlite`. The fixture seeder is deterministic (fixed UUIDs and timestamps) so git diffs are minimal when the schema evolves.

---

## Required Data Coverage

### 1. Jobs — Status Coverage

One job per status so every sidebar filter and status-change flow can be tested:

| Status | Count | Notes |
|---|---|---|
| `.new` | 3 | Mix of remote/onsite/hybrid; one with no location |
| `.pursuing` | 4 | Variety of companies and seniority levels |
| `.applied` | 5 | Various apply dates (1 day ago, 1 week, 1 month, 3 months) |
| `.interview` | 3 | One with pending `JobAction` (follow-up due) |
| `.offer` | 2 | One accepted (for display), one pending decision |
| `.rejected` | 4 | Mix of pre-screen and post-interview rejections |
| `.passed` | 3 | Passed on by candidate |
| `.archived` | 3 | Manually archived |
| `.closed` | 2 | Position filled externally |
| `.expired` | 4 | JD URL confirmed dead (HTTP 404 or redirect to homepage) |

**Total**: ~33 jobs, enough to exercise every code path without being slow.

### 2. Jobs — Data Quality Coverage

At least one job per `QualityIssueKind`:

| Issue kind | Setup |
|---|---|
| `missingTitle` | Job with `title = nil`, status `.new` (active, so it appears in DataQuality view) |
| `missingCompany` | Job with `company = nil` |
| `missingLocation` | Job with `location = nil` |
| `extractionPending` | Job with `extractionStatus = .pending` |
| `extractionFailed` | Job with `extractionStatus = .failed` |
| `lowConfidence` | Job with `extractionConfidence < 0.6` |
| `staleApplication` | Job with `status = .applied`, `appliedAt` > 30 days ago, no follow-up action |

### 3. Jobs — Duplicate Coverage

Three duplicate groups:
- **Exact URL duplicates**: 2 jobs pointing to the same canonical URL (different capture times)
- **Title+company duplicates**: 2 jobs from different sites for the same role at the same company (different URLs)
- **Near-duplicate**: 2 jobs with 90% title similarity at the same company

All duplicates have `duplicateOfJobID` set on the non-primary copy so the Duplicates view is populated.

### 4. Jobs — LLM Extraction Coverage

| State | Count | Notes |
|---|---|---|
| `extractionStatus = .notStarted` | 2 | Queued but not yet picked up |
| `extractionStatus = .pending` | 3 | Mid-flight (simulated in fixture by setting status + no result) |
| `extractionStatus = .completed` | All others | Normal |
| `extractionStatus = .failed` | 2 | Permanent failure with error message |
| High confidence extraction | 5 | `extractionConfidence >= 0.9` |
| Low confidence extraction | 3 | `extractionConfidence < 0.6`, all fields populated but uncertain |

### 5. Jobs — Real Job Descriptions

Jobs should use real job description content (not lorem ipsum) to exercise LLM normalization and search. Sources:

- **Live JDs** (verified at fixture creation time): 10 jobs from active postings at well-known companies. Include the full raw HTML/text and the extracted structured fields side-by-side so LLM eval tests can verify extraction quality.
- **Expired JDs** (URL dead): 4 jobs where `sourceURL` returns 404 or redirects. Used to exercise `AvailabilityChecker` and the `.expired` status transition. Store the original captured HTML so the job record is complete even though the URL is dead.
- **Removed JDs** (URL redirects to company homepage): 2 jobs. Different from 404 — the URL technically resolves but the JD is gone.

**Content variety**: Include JDs from software engineering, product management, data science, and design roles. Include remote-only, hybrid, and onsite postings. Include US and international (non-US) postings. Include jobs with and without explicit salary ranges.

### 6. Sites

| Site | State |
|---|---|
| `linkedin.com` | Active, 8 jobs captured |
| `greenhouse.io` (company-specific) | Active, 3 jobs |
| `lever.co` (company-specific) | Active, 2 jobs |
| `indeed.com` | Active, 1 job |
| A dead site (defunct company) | Inactive — `lastCheckedAt` > 60 days, all jobs expired |

### 7. Saved Searches

Three saved searches:
- "Remote Senior Roles" — filters for remote + seniority keywords
- "Applied This Month" — status filter: `.applied`
- "Needs Follow-up" — jobs with overdue pending actions

These exercise the Saved Searches sidebar section and search persistence.

### 8. Job Actions (Pending Follow-ups)

| Action type | Count | State |
|---|---|---|
| `followUp` | 2 | Due today or overdue (exercises Needs Action view) |
| `followUp` | 1 | Due in 7 days (not yet shown in Needs Action) |
| `followUp` | 3 | Completed (`completedAt` set) — exercises completion flow |
| `phoneScreen` | 1 | Pending |
| `onsite` | 1 | Pending |

### 9. Temporal Coverage

Jobs must span a realistic timeline to exercise date-sensitive logic:

- Jobs captured over the past 12 months (not all recent)
- `appliedAt` dates spanning 1 day to 6 months ago
- `AvailabilityChecker` last-checked timestamps: recent (< 24 h), stale (> 7 days), never checked
- At least 2 jobs where the JD URL was live at capture but is now dead (simulated by using URLs that redirect)

---

## Git Storage

### Size management

Raw SQLite can be large. Strategies:
1. **Compact on write**: Run `VACUUM` before committing. Typical fixture should be < 2 MB.
2. **Git LFS**: If the fixture grows beyond 5 MB, store via Git LFS. Add `tests/fixtures/*.sqlite filter=lfs diff=lfs merge=lfs -text` to `.gitattributes`.
3. **No binary blobs in jobs**: Store JD content as text (not HTML with embedded images). Strip `<img>` tags when seeding.

### Diff strategy

To keep git diffs readable when the fixture changes, the `seed-test-db.sh` script:
1. Exports the fixture to a deterministic JSON manifest (`tests/fixtures/jobhunt-test-manifest.json`) alongside the SQLite file
2. The manifest lists all records with human-readable field values (no binary blobs)
3. PR reviewers can diff the JSON to understand what changed in the fixture, even if the SQLite binary diff is opaque

---

## Implementation Plan

### Phase 1 — Infrastructure (prerequisite)

1. Add `--fixture-db <path>` launch arg to `app/JobhuntApp.swift`: copy the file to a temp path and open that container.
2. Add `ModelContainerFactory.fixture(copying:)` to `JobhuntCore` for use in unit tests.
3. Add `FixtureSeeder` class to `core/Demo/` (separate from `DemoSeeder`): deterministic UUIDs, fixed timestamps relative to seeding date, real JD content.
4. Write `scripts/seed-test-db.sh`.
5. Add `tests/fixtures/` to `.gitignore` exclusion (currently ignored by a glob — add explicit allow).

### Phase 2 — Initial fixture

6. Curate the JD content: find 10 live postings, 4 confirmed-dead URLs. Store raw text.
7. Run `seed-test-db.sh` to generate `tests/fixtures/jobhunt-test.sqlite` and the JSON manifest.
8. Commit both files.

### Phase 3 — Test migration

9. Update `AppUITests` `launchApp()` to accept a `fixture:` parameter that passes `--fixture-db`.
10. Migrate `testDataQualityFilterChipAccessibleState` to use fixture DB (guarantees `missingTitle` chip appears).
11. Migrate `testArchive_seededJob_movesJobToArchived` to use fixture DB (guarantees an archiveable job exists).
12. Migrate `AvailabilityCheckerTests` to use fixture DB (exercises real expired URL scenarios).

### Phase 4 — Maintenance process

13. Document in `docs/vm-testing.md` how to update the fixture (re-run seeder, commit both files).
14. Add a `CoreTests` test that validates the fixture has the expected row counts and status distribution, so fixture corruption is caught before tests start.

---

## What DemoSeeder Keeps Doing

`DemoSeeder` is NOT replaced. It continues to be used for:
- In-app demo mode (Help → Load Demo Data)
- Quick smoke tests where data variety doesn't matter
- Any test where the simplicity of in-memory seeding is preferable

The fixture DB supplements DemoSeeder for tests that need real-world data fidelity.

---

## Open Questions

1. **JD URL expiration**: Live URLs will die over time. Should the fixture be refreshed on a schedule (e.g., quarterly), or should all "live" JD URLs in the fixture use stable test pages (e.g., a controlled web server or archived copies)? Recommendation: use a mix — a few real URLs as a live canary, the rest archived so the fixture doesn't rot.

2. **SwiftData schema migration**: When the SwiftData schema changes (new `VersionedSchema`), the fixture SQLite needs to be migrated. The `MigratorTests` already cover migration correctness; the fixture should be kept at the latest schema version and regenerated after each migration.

3. **CI access**: The fixture lives in the repo, so CI gets it for free via checkout. No additional setup needed.
