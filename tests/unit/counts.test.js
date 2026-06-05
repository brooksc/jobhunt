import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { countDuplicatePairs, buildDailyActivity, activityTotal } from '../../static/counts.js';
import { buildMetrics, DB_STATUS_TO_UI } from '../../server/api.js';

// ── countDuplicatePairs ───────────────────────────────────────────────────────

describe('countDuplicatePairs', () => {
  it('returns 0 for empty array', () => {
    assert.equal(countDuplicatePairs([]), 0);
  });

  it('returns 0 for null/undefined', () => {
    assert.equal(countDuplicatePairs(null), 0);
    assert.equal(countDuplicatePairs(undefined), 0);
  });

  it('single group of 2 → 1 pair', () => {
    assert.equal(countDuplicatePairs([{ jobIds: [1, 2] }]), 1);
  });

  it('single group of 3 → 2 pairs', () => {
    assert.equal(countDuplicatePairs([{ jobIds: [1, 2, 3] }]), 2);
  });

  it('two groups → sum of pairs', () => {
    // group A: 3 jobs → 2 pairs; group B: 2 jobs → 1 pair
    assert.equal(countDuplicatePairs([{ jobIds: [1, 2, 3] }, { jobIds: [4, 5] }]), 3);
  });

  it('group of 1 job → 0 pairs (Math.max guard)', () => {
    assert.equal(countDuplicatePairs([{ jobIds: [1] }]), 0);
  });

  it('matches sidebar formula used before refactor', () => {
    const dupes = [{ jobIds: [10, 20] }, { jobIds: [30, 40, 50] }];
    const inline = dupes.reduce((n, g) => n + Math.max(0, (g.jobIds || []).length - 1), 0);
    assert.equal(countDuplicatePairs(dupes), inline);
  });
});

// ── buildDailyActivity ────────────────────────────────────────────────────────

describe('buildDailyActivity', () => {
  it('returns empty array for no jobs', () => {
    assert.deepEqual(buildDailyActivity([]), []);
  });

  it('counts capture date as saved', () => {
    const jobs = [{ capturedAt: '2026-06-01T10:00:00Z', events: [] }];
    const rows = buildDailyActivity(jobs);
    assert.equal(rows.length, 1);
    assert.equal(rows[0].date, '2026-06-01');
    assert.equal(rows[0].saved, 1);
    assert.equal(rows[0].applied, 0);
  });

  it('counts applied event on correct date', () => {
    const jobs = [{
      capturedAt: '2026-06-01T10:00:00Z',
      events: [{ kind: 'status', note: 'applied', at: '2026-06-02T12:00:00Z' }],
    }];
    const rows = buildDailyActivity(jobs);
    const jun2 = rows.find(r => r.date === '2026-06-02');
    assert.ok(jun2, 'should have a row for Jun 2');
    assert.equal(jun2.applied, 1);
  });

  it('ignores non-status events', () => {
    const jobs = [{
      capturedAt: '2026-06-01T10:00:00Z',
      events: [{ kind: 'note', note: 'some note', at: '2026-06-01T11:00:00Z' }],
    }];
    const rows = buildDailyActivity(jobs);
    assert.equal(rows[0].applied, 0);
  });

  it('rows are sorted newest-first', () => {
    const jobs = [
      { capturedAt: '2026-06-01T10:00:00Z', events: [] },
      { capturedAt: '2026-06-03T10:00:00Z', events: [] },
    ];
    const rows = buildDailyActivity(jobs);
    assert.equal(rows[0].date, '2026-06-03');
    assert.equal(rows[1].date, '2026-06-01');
  });

  it('REGRESSION: activity total > current status count when jobs progress', () => {
    // A job starts saved, gets applied, then gets rejected.
    // Current status = rejected (0 applied), but activity total = 1 applied.
    // This is intentional: activity tracks what happened, not where things stand.
    const jobs = [
      {
        capturedAt: '2026-05-01T00:00:00Z',
        status: 'rejected',
        events: [
          { kind: 'status', note: 'applied',  at: '2026-05-10T00:00:00Z' },
          { kind: 'status', note: 'rejected', at: '2026-05-20T00:00:00Z' },
        ],
      },
      {
        capturedAt: '2026-05-02T00:00:00Z',
        status: 'applied',
        events: [
          { kind: 'status', note: 'applied', at: '2026-05-11T00:00:00Z' },
        ],
      },
    ];

    const currentApplied = jobs.filter(j => j.status === 'applied').length;
    const rows = buildDailyActivity(jobs);
    const totalApplied = activityTotal(rows, 'applied');

    assert.equal(currentApplied, 1, 'only 1 job currently applied');
    assert.equal(totalApplied, 2, 'but 2 applied events in history');
    assert.ok(totalApplied > currentApplied, 'activity total intentionally exceeds current count');
  });
});

// ── buildMetrics ──────────────────────────────────────────────────────────────

describe('buildMetrics', () => {
  it('counts jobs by current status', () => {
    const jobs = [
      { status: 'saved',     extraction_status: null },
      { status: 'applied',   extraction_status: null },
      { status: 'applied',   extraction_status: null },
      { status: 'interview', extraction_status: null },
    ];
    const m = buildMetrics(jobs, [], [], 0);
    assert.equal(m.saved, 1);
    assert.equal(m.applied, 2);
    assert.equal(m.interview, 1);
    assert.equal(m.jobs, 4);
  });

  it('DB_STATUS_TO_UI aliases map correctly', () => {
    const jobs = [
      { status: 'interested',  extraction_status: null }, // → saved
      { status: 'interviewing', extraction_status: null }, // → interview
      { status: 'closed',      extraction_status: null }, // → archived
      { status: 'ignored',     extraction_status: null }, // → archived
    ];
    const m = buildMetrics(jobs, [], [], 0);
    assert.equal(m.saved, 1,     'interested → saved');
    assert.equal(m.interview, 1, 'interviewing → interview');
    assert.equal(m.archived, 2,  'closed + ignored → archived');
  });

  it('duplicateGroups matches dupes.length', () => {
    const dupes = [
      { job_ids: [1, 2] },
      { job_ids: [3, 4, 5] },
    ];
    const m = buildMetrics([], [], dupes, 0);
    assert.equal(m.duplicateGroups, 2);
  });

  it('sidebar pairs count = sum of (job_ids.length - 1)', () => {
    // Verify the relationship between duplicateGroups (sidebar was using this)
    // and the correct pairs formula. duplicateGroups != pairs when any group has >2 jobs.
    const dupes = [
      { job_ids: [1, 2] },      // 1 pair
      { job_ids: [3, 4, 5] },   // 2 pairs
    ];
    const m = buildMetrics([], [], dupes, 0);
    const pairs = dupes.reduce((n, d) => n + Math.max(0, d.job_ids.length - 1), 0);
    assert.equal(m.duplicateGroups, 2, 'groups = 2');
    assert.equal(pairs, 3, 'pairs = 3');
    assert.notEqual(m.duplicateGroups, pairs, 'groups != pairs when any group has >2 jobs');
  });

  it('needsAction passes through', () => {
    const m = buildMetrics([], [], [], 7);
    assert.equal(m.needsAction, 7);
  });

  it('sites count = sites.length', () => {
    const m = buildMetrics([], [{ id: 1 }, { id: 2 }], [], 0);
    assert.equal(m.sites, 2);
  });
});

// ── DB_STATUS_TO_UI completeness ──────────────────────────────────────────────

describe('DB_STATUS_TO_UI', () => {
  it('maps all legacy statuses', () => {
    assert.equal(DB_STATUS_TO_UI.interested, 'saved');
    assert.equal(DB_STATUS_TO_UI.interviewing, 'interview');
    assert.equal(DB_STATUS_TO_UI.closed, 'archived');
    assert.equal(DB_STATUS_TO_UI.ignored, 'archived');
  });
});
