import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { sortValue, sortJobs } from '../../static/sort.js';

// Minimal job stubs — only fields each sort key needs.
const job = (overrides = {}) => ({
  salaryMin: null, salaryMax: null, salaryNote: null,
  rating: null,
  fit: { score: null },
  extraction: { status: 'succeeded', at: '2025-01-01T00:00:00Z' },
  lastOpenedAt: null,
  lastStatusChangedAt: null,
  nextAction: null,
  capturedAt: '2025-01-01T00:00:00Z',
  company: 'Acme', title: 'Engineer', status: 'saved',
  ...overrides,
});

// ----------------------------------------------------------------
// sortValue — per-key unit tests
// ----------------------------------------------------------------

describe('sortValue — fitScore', () => {
  it('returns the numeric score when present', () => {
    assert.equal(sortValue(job({ fit: { score: 93 } }), 'fitScore'), 93);
  });

  it('returns sentinel for null score so unscored jobs sort last', () => {
    const v = sortValue(job({ fit: { score: null } }), 'fitScore');
    // Sentinel must be null so the empty-check in sortJobs pushes it to the end.
    // Current implementation returns -1, which bypasses the empty-check and
    // causes unscored jobs to sort BEFORE scored jobs in ascending order.
    assert.equal(v, null, 'unscored job should return null, not -1');
  });

  it('returns null when fit object is absent', () => {
    const v = sortValue(job({ fit: undefined }), 'fitScore');
    assert.equal(v, null);
  });
});

describe('sortValue — salary', () => {
  it('salaryMin falls back to salaryMax when min is null', () => {
    assert.equal(sortValue(job({ salaryMin: null, salaryMax: 200000 }), 'salaryMin'), 200000);
  });

  it('salaryMax falls back to salaryMin when max is null', () => {
    assert.equal(sortValue(job({ salaryMin: 150000, salaryMax: null }), 'salaryMax'), 150000);
  });

  it('returns null when both salary fields are null', () => {
    assert.equal(sortValue(job(), 'salaryMin'), null);
    assert.equal(sortValue(job(), 'salaryMax'), null);
  });
});

describe('sortValue — rating', () => {
  it('returns the rating when set', () => {
    assert.equal(sortValue(job({ rating: 4 }), 'rating'), 4);
  });

  it('returns null when rating is null', () => {
    assert.equal(sortValue(job({ rating: null }), 'rating'), null);
  });
});

describe('sortValue — string fields', () => {
  it('returns company string', () => {
    assert.equal(sortValue(job({ company: 'Google' }), 'company'), 'Google');
  });

  it('returns empty string for null field', () => {
    assert.equal(sortValue(job({ company: null }), 'company'), '');
  });

  it('returns extractionStatus from extraction object', () => {
    assert.equal(sortValue(job({ extraction: { status: 'failed', at: '' } }), 'extractionStatus'), 'failed');
  });

  it('returns lastOpenedAt string', () => {
    const j = job({ lastOpenedAt: '2025-06-01T00:00:00Z' });
    assert.equal(sortValue(j, 'lastOpenedAt'), '2025-06-01T00:00:00Z');
  });

  it('returns empty string for null lastOpenedAt', () => {
    assert.equal(sortValue(job(), 'lastOpenedAt'), '');
  });

  it('returns nextActionDue from nextAction object', () => {
    const j = job({ nextAction: { dueDate: '2025-07-01', note: 'Follow up' } });
    assert.equal(sortValue(j, 'nextActionDue'), '2025-07-01');
  });

  it('returns empty string when nextAction is null', () => {
    assert.equal(sortValue(job(), 'nextActionDue'), '');
  });
});

// ----------------------------------------------------------------
// sortJobs — end-to-end ordering tests
// ----------------------------------------------------------------

describe('sortJobs — fitScore ascending', () => {
  it('sorts scored jobs low to high', () => {
    const a = job({ fit: { score: 40 } });
    const b = job({ fit: { score: 90 } });
    const c = job({ fit: { score: 60 } });
    const result = sortJobs([b, c, a], { key: 'fitScore', dir: 'asc' });
    assert.deepEqual(result.map(j => j.fit.score), [40, 60, 90]);
  });

  it('places unscored jobs AFTER scored jobs in ascending order', () => {
    const scored = job({ fit: { score: 93 } });
    const unscored = job({ fit: { score: null } });
    const result = sortJobs([unscored, scored], { key: 'fitScore', dir: 'asc' });
    assert.equal(result[0].fit.score, 93, 'scored job should be first in asc');
    assert.equal(result[1].fit.score, null, 'unscored job should be last in asc');
  });

  it('places unscored jobs AFTER scored jobs in descending order', () => {
    const scored = job({ fit: { score: 30 } });
    const unscored = job({ fit: { score: null } });
    const result = sortJobs([unscored, scored], { key: 'fitScore', dir: 'desc' });
    assert.equal(result[0].fit.score, 30, 'scored job should be first in desc');
    assert.equal(result[1].fit.score, null, 'unscored job should be last in desc');
  });

  it('handles multiple unscored jobs stably', () => {
    const a = job({ fit: { score: 50 }, company: 'A' });
    const b = job({ fit: { score: null }, company: 'B' });
    const c = job({ fit: { score: null }, company: 'C' });
    const result = sortJobs([b, a, c], { key: 'fitScore', dir: 'asc' });
    assert.equal(result[0].fit.score, 50);
    assert.equal(result[1].fit.score, null);
    assert.equal(result[2].fit.score, null);
  });
});

describe('sortJobs — fitScore descending', () => {
  it('sorts scored jobs high to low', () => {
    const a = job({ fit: { score: 40 } });
    const b = job({ fit: { score: 90 } });
    const c = job({ fit: { score: 60 } });
    const result = sortJobs([a, c, b], { key: 'fitScore', dir: 'desc' });
    assert.deepEqual(result.map(j => j.fit.score), [90, 60, 40]);
  });
});

describe('sortJobs — salary', () => {
  it('sorts by salaryMin ascending', () => {
    const a = job({ salaryMin: 100000 });
    const b = job({ salaryMin: 200000 });
    const c = job({ salaryMin: 150000 });
    const result = sortJobs([b, c, a], { key: 'salaryMin', dir: 'asc' });
    assert.deepEqual(result.map(j => j.salaryMin), [100000, 150000, 200000]);
  });

  it('places zero-salary jobs after salaried jobs in ascending', () => {
    const salaried = job({ salaryMin: 120000 });
    const unsalaried = job({ salaryMin: null, salaryMax: null });
    const result = sortJobs([unsalaried, salaried], { key: 'salaryMin', dir: 'asc' });
    assert.equal(result[0].salaryMin, 120000);
    assert.equal(result[1].salaryMin, null);
  });
});

describe('sortJobs — string fields', () => {
  it('sorts company alphabetically ascending', () => {
    const jobs = [
      job({ company: 'Zoom' }),
      job({ company: 'Acme' }),
      job({ company: 'Meta' }),
    ];
    const result = sortJobs(jobs, { key: 'company', dir: 'asc' });
    assert.deepEqual(result.map(j => j.company), ['Acme', 'Meta', 'Zoom']);
  });

  it('sorts company alphabetically descending', () => {
    const jobs = [
      job({ company: 'Zoom' }),
      job({ company: 'Acme' }),
      job({ company: 'Meta' }),
    ];
    const result = sortJobs(jobs, { key: 'company', dir: 'desc' });
    assert.deepEqual(result.map(j => j.company), ['Zoom', 'Meta', 'Acme']);
  });

  it('sorts capturedAt as ISO string (newest first in desc)', () => {
    const a = job({ capturedAt: '2025-01-01T00:00:00Z' });
    const b = job({ capturedAt: '2025-06-01T00:00:00Z' });
    const c = job({ capturedAt: '2025-03-01T00:00:00Z' });
    const result = sortJobs([a, b, c], { key: 'capturedAt', dir: 'desc' });
    assert.equal(result[0].capturedAt, '2025-06-01T00:00:00Z');
    assert.equal(result[2].capturedAt, '2025-01-01T00:00:00Z');
  });

  it('places empty-string fields after non-empty in ascending', () => {
    const a = job({ company: 'Acme' });
    const b = job({ company: null });
    const result = sortJobs([b, a], { key: 'company', dir: 'asc' });
    assert.equal(result[0].company, 'Acme');
    assert.equal(result[1].company, null);
  });
});

describe('sortJobs — rating', () => {
  it('sorts by rating ascending, unrated last', () => {
    const a = job({ rating: 5 });
    const b = job({ rating: null });
    const c = job({ rating: 3 });
    const result = sortJobs([b, a, c], { key: 'rating', dir: 'asc' });
    assert.deepEqual(result.map(j => j.rating), [3, 5, null]);
  });
});
