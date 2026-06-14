# Test Fixtures

## What is `jobhunt-test.sqlite`?

A pre-seeded SQLite database used by unit and UI tests that need real data without
running a live LLM pipeline or touching the user's production store.

## What's in it?

Populated by `FixtureSeeder`:

- **Jobs** covering every `JobStatus` value (pursuing, applied, interview, offer, rejected, passed)
- **Data quality issues** — one of each `DataQualityIssueKind` (missing fields, low confidence, etc.)
- **Duplicate groups** — at least one pair of jobs flagged as duplicates
- **Sites**, **resumes**, and associated events

## How to regenerate

Run whenever `FixtureSeeder.swift` changes:

```bash
./scripts/build-fixture-db.sh
```

Add `--rebuild` if you need to regenerate the Xcode project first:

```bash
./scripts/build-fixture-db.sh --rebuild
```

Commit the updated `jobhunt-test.sqlite` to git.

## How tests use it

Tests copy the fixture to a temp path at startup and work against the copy.
The committed file is **never modified** by any test run.
