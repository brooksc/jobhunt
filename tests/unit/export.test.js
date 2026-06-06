import { describe, it, before, after } from 'node:test';
import assert from 'node:assert/strict';
import { initDb, insertCapture, markExtractionSucceeded } from '../../server/db.js';
import { jobsCsv } from '../../server/export.js';
import { tempDbPath, cleanupDb } from '../helpers.js';

const BASE_EXTRACTED = {
  company: 'Acme', title: 'TPM', location: 'Remote', remote_type: 'remote',
  salary_min: 120000, salary_max: 200000, salary_currency: 'USD', salary_note: '$120k-$200k',
  employment_type: 'full_time', seniority: 'senior', skills: [],
  summary: '', requirements: [], nice_to_haves: [], benefits: [],
  application_url: 'https://apply.example.com', confidence: {},
};

describe('jobsCsv', () => {
  let dbPath;
  before(() => { dbPath = tempDbPath(); initDb(dbPath); });
  after(() => cleanupDb(dbPath));

  it('returns only the header row for an empty database', () => {
    const csv = jobsCsv(dbPath);
    const lines = csv.trim().split('\n');
    assert.equal(lines.length, 1);
    assert.ok(lines[0].startsWith('job_number,'));
    assert.ok(lines[0].includes('company'));
    assert.ok(lines[0].includes('title'));
  });

  it('produces one data row per job with correct field values', () => {
    const { job_id } = insertCapture({
      url: 'https://example.com/csv/1',
      page_title: 'TPM at Acme',
      visible_text: 'Job description text here',
    }, dbPath);
    markExtractionSucceeded(job_id, BASE_EXTRACTED, dbPath, null, 'test-model', 0.9);
    const lines = jobsCsv(dbPath).trim().split('\n');
    assert.equal(lines.length, 2);
    assert.ok(lines[1].includes('Acme'));
    assert.ok(lines[1].includes('TPM'));
    assert.ok(lines[1].includes('Remote'));
  });

  it('wraps fields containing commas in double-quotes', () => {
    const { job_id } = insertCapture({
      url: 'https://example.com/csv/2',
      page_title: 'Engineer',
      visible_text: 'Job',
    }, dbPath);
    markExtractionSucceeded(job_id, { ...BASE_EXTRACTED, salary_note: '$100k, OTE' }, dbPath, null, 'test-model', 0.9);
    const csv = jobsCsv(dbPath);
    assert.ok(csv.includes('"$100k, OTE"'));
  });

  it('escapes double-quotes within fields by doubling them', () => {
    const { job_id } = insertCapture({
      url: 'https://example.com/csv/3',
      page_title: 'Engineer',
      visible_text: 'Job',
    }, dbPath);
    markExtractionSucceeded(job_id, { ...BASE_EXTRACTED, title: 'Staff "Platform" Engineer' }, dbPath, null, 'test-model', 0.9);
    const csv = jobsCsv(dbPath);
    assert.ok(csv.includes('"Staff ""Platform"" Engineer"'));
  });

  it('wraps fields containing newlines in double-quotes', () => {
    const { job_id } = insertCapture({
      url: 'https://example.com/csv/5',
      page_title: 'Engineer',
      visible_text: 'Job',
    }, dbPath);
    markExtractionSucceeded(job_id, { ...BASE_EXTRACTED, salary_note: 'Base: $100k\nBonus: $20k' }, dbPath, null, 'test-model', 0.9);
    const csv = jobsCsv(dbPath);
    assert.ok(csv.includes('"Base: $100k\nBonus: $20k"'));
  });

  it('uses page_title as fallback when extracted title is null', () => {
    const { job_id } = insertCapture({
      url: 'https://example.com/csv/4',
      page_title: 'Fallback Page Title',
      visible_text: 'Job description',
    }, dbPath);
    markExtractionSucceeded(job_id, { ...BASE_EXTRACTED, title: null, company: null }, dbPath, null, 'test-model', 0.9);
    const csv = jobsCsv(dbPath);
    assert.ok(csv.includes('Fallback Page Title'));
  });
});
