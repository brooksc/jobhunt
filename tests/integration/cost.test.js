import { describe, it, before, after } from 'node:test';
import assert from 'node:assert/strict';
import { createApp } from '../../server/api.js';
import {
  initDb, insertCapture, markExtractionSucceeded, addResume, markFitSucceeded,
} from '../../server/db.js';
import { promptOverheadChars } from '../../server/extract.js';
import { tempDbPath, cleanupDb, CAPTURE } from '../helpers.js';

const EXTRACTED = {
  company: 'Acme', title: 'Staff TPM', location: 'Remote', remote_type: 'remote',
  salary_min: null, salary_max: null, salary_currency: null, salary_note: null,
  employment_type: 'full_time', seniority: 'staff', skills: ['program management'],
  summary: 'Lead programs.', requirements: ['8+ years TPM'], nice_to_haves: [], benefits: [],
  application_url: null, confidence: {},
};

describe('promptOverheadChars', () => {
  it('returns positive extraction and fit overhead', () => {
    const o = promptOverheadChars();
    assert.ok(o.extractChars > 100);
    assert.ok(o.fitChars > 100);
  });
});

describe('GET /api/llm-cost', () => {
  let base, server, dbPath;
  before(async () => {
    dbPath = tempDbPath();
    initDb(dbPath);
    const app = createApp({ dbPath, autoExtract: false });
    await new Promise(r => { server = app.listen(0, '127.0.0.1', r); });
    base = `http://127.0.0.1:${server.address().port}`;
  });
  after(async () => { await new Promise(r => server.close(r)); cleanupDb(dbPath); });

  it('reports no data on a fresh DB', async () => {
    const c = await (await fetch(`${base}/api/llm-cost`)).json();
    assert.equal(c.has_data, false);
    assert.equal(c.jobs_total, 0);
    assert.equal(c.all.extraction.input_tokens, 0);
    assert.equal(c.all.fit.input_tokens, 0);
  });

  it('computes token totals once jobs and resumes exist', async () => {
    const { job_id } = insertCapture(CAPTURE, dbPath);
    markExtractionSucceeded(job_id, EXTRACTED, dbPath, null, 'm', 0.9);
    const resume = addResume(dbPath, { name: 'R', text: 'experienced staff technical program manager ' .repeat(40) });
    markFitSucceeded(job_id, resume.id, { overall_score: 80, summary: 'good', dimensions: [] }, dbPath, null, 'm');

    const c = await (await fetch(`${base}/api/llm-cost`)).json();
    assert.equal(c.has_data, true);
    assert.equal(c.jobs_total, 1);
    assert.equal(c.resumes_active, 1);
    assert.equal(c.fit_pairs_total, 1);
    assert.equal(c.fit_pairs_done, 1);

    // Extraction + fit each consume input and output tokens.
    assert.ok(c.all.extraction.input_tokens > 0);
    assert.ok(c.all.extraction.output_tokens > 0);
    assert.ok(c.all.fit.input_tokens > 0);
    assert.ok(c.all.fit.output_tokens > 0);

    // Everything is processed → nothing remaining.
    assert.equal(c.remaining.extraction.input_tokens, 0);
    assert.equal(c.remaining.fit.input_tokens, 0);

    // Single job → per-job equals the all-jobs totals.
    assert.equal(c.per_job.extraction.input_tokens, c.all.extraction.input_tokens);
    assert.equal(c.per_job.fit.input_tokens, c.all.fit.input_tokens);
  });

  it('counts unprocessed work as remaining', async () => {
    // A second job that has not been extracted yet.
    insertCapture({ ...CAPTURE, url: 'https://example.com/unprocessed', raw_hash: undefined, page_title: 'Pending Job', visible_text: 'A pending job description with enough text to score. '.repeat(20) }, dbPath);
    const c = await (await fetch(`${base}/api/llm-cost`)).json();
    assert.equal(c.jobs_total, 2);
    assert.equal(c.jobs_extracted, 1);
    // The pending job contributes to remaining extraction, and its unscored
    // resume pair contributes to remaining fit.
    assert.ok(c.remaining.extraction.input_tokens > 0);
    assert.ok(c.remaining.fit.input_tokens > 0);
    // Remaining never exceeds the all-jobs totals.
    assert.ok(c.remaining.extraction.input_tokens <= c.all.extraction.input_tokens);
    assert.ok(c.remaining.fit.input_tokens <= c.all.fit.input_tokens);
  });
});
