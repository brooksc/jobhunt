import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import {
  toStringArray, mapStatus, mapRemote, mapEmployment, mapExtractionStatus, mapJobFields,
} from '../../static/transform.js';

describe('toStringArray', () => {
  it('passes arrays through unchanged', () => {
    assert.deepEqual(toStringArray(['a', 'b']), ['a', 'b']);
    assert.deepEqual(toStringArray([]), []);
  });

  it('wraps a non-empty string in an array', () => {
    assert.deepEqual(toStringArray('Must have 5 years exp.'), ['Must have 5 years exp.']);
  });

  it('returns [] for null, undefined, and empty string', () => {
    assert.deepEqual(toStringArray(null), []);
    assert.deepEqual(toStringArray(undefined), []);
    assert.deepEqual(toStringArray(''), []);
  });

  it('coerces non-string, non-array scalars', () => {
    assert.deepEqual(toStringArray(42), ['42']);
  });
});

describe('mapStatus', () => {
  it('passes canonical statuses through', () => {
    for (const s of ['saved', 'applied', 'offer', 'rejected', 'archived', 'duplicate']) {
      assert.equal(mapStatus(s), s);
    }
  });

  it('maps legacy statuses', () => {
    assert.equal(mapStatus('interested'), 'saved');
    assert.equal(mapStatus('interviewing'), 'interview');
    assert.equal(mapStatus('closed'), 'archived');
    assert.equal(mapStatus('ignored'), 'archived');
  });

  it('passes through unknown statuses unchanged', () => {
    assert.equal(mapStatus('unknown_status'), 'unknown_status');
  });
});

describe('mapRemote', () => {
  it('maps known values', () => {
    assert.equal(mapRemote('remote'), 'Remote');
    assert.equal(mapRemote('hybrid'), 'Hybrid');
    assert.equal(mapRemote('onsite'), 'Onsite');
    assert.equal(mapRemote('unknown'), '—');
  });

  it('returns — for null/undefined', () => {
    assert.equal(mapRemote(null), '—');
    assert.equal(mapRemote(undefined), '—');
  });
});

describe('mapEmployment', () => {
  it('maps full_time variants', () => {
    assert.equal(mapEmployment('full_time'), 'Full-time');
    assert.equal(mapEmployment('fulltime'), 'Full-time');
    assert.equal(mapEmployment('full-time'), 'Full-time');
  });

  it('returns — for null', () => {
    assert.equal(mapEmployment(null), '—');
  });
});

describe('mapExtractionStatus', () => {
  it('maps known values', () => {
    assert.equal(mapExtractionStatus('succeeded'), 'ok');
    assert.equal(mapExtractionStatus('failed'), 'fail');
    assert.equal(mapExtractionStatus('pending'), 'pending');
    assert.equal(mapExtractionStatus(null), 'pending');
  });
});

describe('mapJobFields — array field safety', () => {
  const baseRow = {
    job_id: 'job_001', job_number: 1, status: 'saved',
    company: 'Acme', title: 'Engineer', remote_type: 'remote',
    extraction_status: 'succeeded', fit_status: 'none', unread: 0,
  };

  it('requirements as array passes through', () => {
    const job = mapJobFields(baseRow, { requirements: ['5 years exp', 'Python'] });
    assert(Array.isArray(job.requirements));
    assert.deepEqual(job.requirements, ['5 years exp', 'Python']);
  });

  it('requirements as string (legacy DB data) is wrapped in array', () => {
    const job = mapJobFields(baseRow, { requirements: 'Must have 5 years exp.' });
    assert(Array.isArray(job.requirements));
    assert.equal(job.requirements.length, 1);
    assert.equal(job.requirements[0], 'Must have 5 years exp.');
  });

  it('null/missing requirements yields empty array', () => {
    const job = mapJobFields(baseRow, { requirements: null });
    assert.deepEqual(job.requirements, []);
    const job2 = mapJobFields(baseRow, {});
    assert.deepEqual(job2.requirements, []);
  });

  it('same safety applies to skills, niceToHaves, benefits', () => {
    const extracted = {
      skills: 'Python',
      nice_to_haves: 'Docker experience',
      benefits: '401k',
    };
    const job = mapJobFields(baseRow, extracted);
    assert(Array.isArray(job.skills));
    assert(Array.isArray(job.niceToHaves));
    assert(Array.isArray(job.benefits));
  });

  it('null extracted_json yields empty arrays', () => {
    const job = mapJobFields(baseRow, null);
    assert.deepEqual(job.requirements, []);
    assert.deepEqual(job.skills, []);
    assert.deepEqual(job.benefits, []);
  });
});
