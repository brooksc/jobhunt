import { describe, it, before, after } from 'node:test';
import assert from 'node:assert/strict';
import { createApp } from '../../server/api.js';
import {
  finishLlmRequestAttempt,
  initDb,
  markExtractionSucceeded,
  markFitSucceeded,
  markLlmRequestRunning,
  resetJobExtraction,
  startLlmRequestAttempt,
} from '../../server/db.js';
import { tempDbPath, cleanupDb, CAPTURE, CAPTURE2 } from '../helpers.js';

// Shared server for all API tests — one DB, one Express instance.
let base;
let server;
let dbPath;

before(async () => {
  dbPath = tempDbPath();
  initDb(dbPath);
  const app = createApp({ dbPath, autoExtract: false });
  await new Promise(resolve => {
    server = app.listen(0, '127.0.0.1', resolve);
  });
  base = `http://127.0.0.1:${server.address().port}`;
});

after(async () => {
  await new Promise(resolve => server.close(resolve));
  cleanupDb(dbPath);
});

async function post(path, body) {
  return fetch(`${base}${path}`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(body),
  });
}

async function patch(path, body) {
  return fetch(`${base}${path}`, {
    method: 'PATCH',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(body),
  });
}

async function del(path, body) {
  return fetch(`${base}${path}`, {
    method: 'DELETE',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(body),
  });
}

describe('GET /health', () => {
  it('returns 200 with ok:true', async () => {
    const res = await fetch(`${base}/health`);
    assert.equal(res.status, 200);
    const body = await res.json();
    assert.equal(body.ok, true);
    assert.equal(body.service, 'jobhunt');
  });
});

describe('OPTIONS extension write endpoints', () => {
  it('allows Chrome extension private-network preflight on captures', async () => {
    const res = await fetch(`${base}/captures`, {
      method: 'OPTIONS',
      headers: {
        Origin: 'chrome-extension://abcdefghijklmnopabcdefghijklmnop',
        'Access-Control-Request-Method': 'POST',
        'Access-Control-Request-Headers': 'content-type',
        'Access-Control-Request-Private-Network': 'true',
      },
    });

    assert.equal(res.status, 204);
    assert.equal(res.headers.get('access-control-allow-origin'), 'chrome-extension://abcdefghijklmnopabcdefghijklmnop');
    assert.equal(res.headers.get('access-control-allow-private-network'), 'true');
    assert.match(res.headers.get('access-control-allow-methods'), /POST/);
  });
});

describe('GET /api/settings', () => {
  it('returns settings with defaults', async () => {
    const res = await fetch(`${base}/api/settings`);
    assert.equal(res.status, 200);
    const body = await res.json();
    assert.ok('llm_base_url' in body);
    assert.ok('llm_model' in body);
  });
});

describe('PATCH /api/settings', () => {
  it('persists a setting', async () => {
    const res = await patch('/api/settings', { llm_model: 'test-model-xyz' });
    assert.equal(res.status, 200);
    const check = await (await fetch(`${base}/api/settings`)).json();
    assert.equal(check.llm_model, 'test-model-xyz');
  });
});

describe('POST /captures', () => {
  it('returns 400 when url is missing', async () => {
    const res = await post('/captures', { page_title: 'x', visible_text: 'hello' });
    assert.equal(res.status, 400);
  });

  it('returns 400 when visible_text and selected_text are both missing', async () => {
    const res = await post('/captures', { url: 'https://x.com', page_title: 'x' });
    assert.equal(res.status, 400);
  });

  it('creates a new capture', async () => {
    const res = await post('/captures', CAPTURE);
    assert.equal(res.status, 200);
    const body = await res.json();
    assert.equal(body.ok, true);
    assert.ok(body.capture_id);
    assert.equal(body.duplicate, false);
  });

  it('returns duplicate:true for same content', async () => {
    const res = await post('/captures', CAPTURE);
    assert.equal(res.status, 200);
    const body = await res.json();
    assert.equal(body.duplicate, true);
  });
});

describe('GET /api/ui-data', () => {
  it('returns jobs array', async () => {
    const res = await fetch(`${base}/api/ui-data`);
    assert.equal(res.status, 200);
    const body = await res.json();
    assert.ok(Array.isArray(body.jobs));
    assert.ok(body.jobs.length >= 1, 'should have at least the capture posted above');
  });

  it('includes expected job fields', async () => {
    const res = await fetch(`${base}/api/ui-data`);
    const { jobs } = await res.json();
    const job = jobs[0];
    for (const field of [
      'job_id', 'job_number', 'status', 'company', 'title', 'location', 'remote_type',
      'salary_min', 'salary_max', 'salary_currency', 'salary_note', 'extraction_status',
      'extracted_at', 'source_url', 'captured_at', 'rating', 'fit_score', 'fit_status',
      'duplicate_of_job_id', 'visible_byte_size', 'selected_text_present', 'structured_data_count',
    ]) {
      assert.ok(field in job, `expected ${field} in job payload`);
    }
  });
});

describe('PATCH /api/jobs/:jobId/status', () => {
  let jobId;

  before(async () => {
    await post('/captures', CAPTURE2);
    const res = await fetch(`${base}/api/ui-data`);
    const { jobs } = await res.json();
    const job = jobs.find(j => j.source_url === CAPTURE2.url);
    jobId = job.job_id;
  });

  it('updates job status to applied', async () => {
    const res = await patch(`/api/jobs/${jobId}/status`, { status: 'applied' });
    assert.equal(res.status, 200);
    const body = await res.json();
    assert.equal(body.ok, true);

    const check = await fetch(`${base}/api/ui-data`);
    const { jobs } = await check.json();
    const updated = jobs.find(j => j.job_id === jobId);
    assert.equal(updated.status, 'applied');
  });

  it('returns 400 for invalid status', async () => {
    const res = await patch(`/api/jobs/${jobId}/status`, { status: 'nonsense' });
    assert.equal(res.status, 400);
  });
});

describe('PATCH /api/jobs/bulk/status', () => {
  it('updates multiple job statuses', async () => {
    const before = await fetch(`${base}/api/ui-data`);
    const { jobs } = await before.json();
    const jobIds = jobs.slice(0, 2).map(j => j.job_id);
    assert.ok(jobIds.length >= 2, 'expected at least two jobs for bulk status update');

    const res = await patch('/api/jobs/bulk/status', { job_ids: jobIds, status: 'archived' });
    assert.equal(res.status, 200);
    const body = await res.json();
    assert.equal(body.ok, true);
    assert.equal(body.updated, jobIds.length);

    const check = await fetch(`${base}/api/ui-data`);
    const updated = (await check.json()).jobs.filter(j => jobIds.includes(j.job_id));
    assert.equal(updated.length, jobIds.length);
    assert.ok(updated.every(j => j.status === 'archived'));
  });

  it('returns 400 for invalid bulk status', async () => {
    const res = await patch('/api/jobs/bulk/status', { job_ids: ['missing'], status: 'nonsense' });
    assert.equal(res.status, 400);
  });
});

describe('extraction provenance API serialization', () => {
  it('exposes model, application URL, and confidence through /api/ui-data', async () => {
    const capture = {
      ...CAPTURE,
      url: 'https://example.com/provenance-api',
      page_title: 'Provenance API Job',
      visible_text: 'Principal TPM at Acme with apply link.',
    };
    const created = await post('/captures', capture);
    const db = initDb(dbPath);
    const jobId = db.prepare('SELECT id FROM jobs WHERE capture_id=?').get((await created.json()).capture_id).id;

    markExtractionSucceeded(jobId, {
      company: 'Acme',
      title: 'Principal TPM',
      location: 'Seattle, WA',
      remote_type: 'hybrid',
      salary_min: 120000,
      salary_max: 220000,
      salary_currency: 'USD',
      salary_note: '$120k-$220k',
      employment_type: 'full_time',
      seniority: 'principal',
      skills: [],
      summary: 'Owns delivery.',
      requirements: [],
      nice_to_haves: [],
      benefits: [],
      application_url: 'https://apply.example.com/provenance-api',
      confidence: { title: 0.95, company: 0.85 },
    }, dbPath, null, 'test-model-e2b', 0.9);

    const res = await fetch(`${base}/api/ui-data`);
    assert.equal(res.status, 200);
    const { jobs } = await res.json();
    const job = jobs.find(j => j.job_id === jobId);

    assert.equal(job.extraction_model, 'test-model-e2b');
    assert.equal(job.application_url, 'https://apply.example.com/provenance-api');
    assert.equal(job.extraction_confidence, 0.9);
    assert.deepEqual(JSON.parse(job.manual_overrides), []);
    assert.equal(job.extracted_json.application_url, 'https://apply.example.com/provenance-api');
    assert.deepEqual(job.extracted_json.confidence, { title: 0.95, company: 0.85 });
  });

  it('exposes fit-score detail JSON through /api/ui-data', async () => {
    const created = await post('/captures', {
      ...CAPTURE,
      url: 'https://example.com/fit-api',
      page_title: 'Fit API Job',
      visible_text: 'Staff TPM with platform and infrastructure scope.',
    });
    const db = initDb(dbPath);
    const jobId = db.prepare('SELECT id FROM jobs WHERE capture_id=?').get((await created.json()).capture_id).id;

    markFitSucceeded(jobId, {
      overall_score: 82,
      summary: 'Strong platform program fit.',
      dimensions: [
        { name: 'required_qualifications', score: 90, rationale: 'Meets most required qualifications.' },
      ],
      requirements_met: ['Program leadership'],
      requirements_not_met: ['Domain-specific compliance'],
    }, dbPath, null, 'fit-model');

    const res = await fetch(`${base}/api/ui-data`);
    assert.equal(res.status, 200);
    const { jobs } = await res.json();
    const job = jobs.find(j => j.job_id === jobId);

    assert.equal(job.fit_score, 82);
    assert.equal(job.fit_status, 'succeeded');
    assert.equal(job.fit_score_json.summary, 'Strong platform program fit.');
    assert.equal(job.fit_score_json.model, 'fit-model');
    assert.deepEqual(job.fit_score_json.requirements_met, ['Program leadership']);
    assert.deepEqual(job.fit_score_json.requirements_not_met, ['Domain-specific compliance']);
  });

  it('exposes failed attempt provenance through the attempts endpoint', async () => {
    const created = await post('/captures', {
      ...CAPTURE2,
      url: 'https://example.com/provenance-failed-attempt',
      page_title: 'Failed Attempt Provenance',
    });
    const db = initDb(dbPath);
    const jobId = db.prepare('SELECT id FROM jobs WHERE capture_id=?').get((await created.json()).capture_id).id;
    const requestId = resetJobExtraction(jobId, dbPath);
    assert.equal(markLlmRequestRunning(requestId, dbPath), true);
    const attemptId = startLlmRequestAttempt(dbPath, requestId, {
      baseUrl: 'http://127.0.0.1:1234',
      modelRequested: 'gemma-test',
      promptChars: 321,
    });
    finishLlmRequestAttempt(dbPath, attemptId, {
      status: 'failed',
      modelReturned: 'gemma-test-returned',
      responseFormat: 'json_schema',
      error: 'LLM response did not contain a JSON object',
      responsePreview: 'plain text response',
      responseChars: 19,
    });

    const res = await fetch(`${base}/api/llm-queue/${encodeURIComponent(requestId)}/attempts`);
    assert.equal(res.status, 200);
    const body = await res.json();
    assert.equal(body.ok, true);
    assert.equal(body.attempts.length, 1);
    assert.equal(body.attempts[0].model_requested, 'gemma-test');
    assert.equal(body.attempts[0].model_returned, 'gemma-test-returned');
    assert.equal(body.attempts[0].response_format, 'json_schema');
    assert.equal(body.attempts[0].base_url, 'http://127.0.0.1:1234');
    assert.equal(body.attempts[0].prompt_chars, 321);
    assert.equal(body.attempts[0].response_chars, 19);
    assert.match(body.attempts[0].error, /JSON object/);
  });
});

describe('data-quality review APIs', () => {
  it('marks and clears reviewed data-quality rows', async () => {
    const created = await post('/captures', {
      ...CAPTURE,
      url: 'https://example.com/api-data-quality-review',
      page_title: 'API Data Quality Review',
      visible_text: 'Weak capture',
    });
    const db = initDb(dbPath);
    const jobId = db.prepare('SELECT id FROM jobs WHERE capture_id=?').get((await created.json()).capture_id).id;

    let res = await post('/api/jobs/bulk/data-quality-reviewed', { job_ids: [jobId], note: 'checked in UI' });
    assert.equal(res.status, 200);
    let body = await res.json();
    assert.equal(body.updated, 1);

    let ui = await (await fetch(`${base}/api/ui-data`)).json();
    assert.ok(ui.jobs.find(j => j.job_id === jobId).data_quality_reviewed_at);

    res = await del('/api/jobs/bulk/data-quality-reviewed', { job_ids: [jobId] });
    assert.equal(res.status, 200);
    body = await res.json();
    assert.equal(body.updated, 1);

    ui = await (await fetch(`${base}/api/ui-data`)).json();
    assert.equal(ui.jobs.find(j => j.job_id === jobId).data_quality_reviewed_at, null);
  });
});

describe('bulk LLM API', () => {
  it('queues missing-field and fit-only work', async () => {
    const missingCreated = await post('/captures', {
      ...CAPTURE,
      url: 'https://example.com/api-bulk-missing',
      page_title: 'API Bulk Missing',
      visible_text: 'Missing location and salary capture',
    });
    const completeCreated = await post('/captures', {
      ...CAPTURE2,
      url: 'https://example.com/api-bulk-complete',
      page_title: 'API Bulk Complete',
      visible_text: 'Complete capture',
    });
    const db = initDb(dbPath);
    const missingJobId = db.prepare('SELECT id FROM jobs WHERE capture_id=?').get((await missingCreated.json()).capture_id).id;
    const completeJobId = db.prepare('SELECT id FROM jobs WHERE capture_id=?').get((await completeCreated.json()).capture_id).id;
    markExtractionSucceeded(completeJobId, {
      company: 'Complete API',
      title: 'Complete API TPM',
      location: 'Seattle, WA',
      remote_type: 'hybrid',
      salary_min: 160000,
      salary_max: 230000,
      salary_currency: 'USD',
      salary_note: '$160k-$230k',
      employment_type: 'full_time',
      seniority: 'senior',
      skills: [],
      summary: '',
      requirements: [],
      nice_to_haves: [],
      benefits: [],
      application_url: null,
      confidence: {},
    }, dbPath, null, 'test-model', 0.8);

    let res = await post('/api/jobs/bulk/llm', { job_ids: [completeJobId, missingJobId], mode: 'missing_fields' });
    assert.equal(res.status, 200);
    let body = await res.json();
    assert.equal(body.queued, 1);
    assert.equal(body.skipped, 1);

    res = await post('/api/jobs/bulk/llm', { job_ids: [completeJobId, missingJobId], mode: 'fit_score' });
    assert.equal(res.status, 200);
    body = await res.json();
    assert.equal(body.queued, 1);
    assert.equal(body.skipped, 1);

    res = await post('/api/jobs/bulk/llm', { job_ids: [completeJobId], mode: 'unknown' });
    assert.equal(res.status, 400);

    const completeNumber = db.prepare('SELECT job_number FROM jobs WHERE id=?').get(completeJobId).job_number;
    res = await post('/api/jobs/bulk/llm-by-number', { job_numbers: [`#${completeNumber}`, 999999], mode: 'extract' });
    assert.equal(res.status, 200);
    body = await res.json();
    assert.equal(body.requested, 2);
    assert.equal(body.found, 1);
    assert.equal(body.queued, 1);
    assert.deepEqual(body.missing_job_numbers, [999999]);
  });
});

describe('POST /api/jobs/:jobId/notes', () => {
  let jobId;

  before(async () => {
    const res = await fetch(`${base}/api/ui-data`);
    const { jobs } = await res.json();
    jobId = jobs[0].job_id;
  });

  it('adds a note to the job', async () => {
    const res = await post(`/api/jobs/${jobId}/notes`, { note: 'Follow up next week' });
    assert.equal(res.status, 200);
    assert.equal((await res.json()).ok, true);
  });
});

describe('site management APIs', () => {
  it('adds, reviews, updates, and ingests site review rows', async () => {
    const add = await post('/api/sites', {
      url: 'https://careers.example.com/jobs',
      page_title: 'Example Careers',
      company_name: 'Example',
      note: 'Initial review',
    });
    assert.equal(add.status, 200);
    const site = await add.json();
    assert.equal(site.origin, 'https://careers.example.com');
    assert.equal(site.company_name, 'Example');

    const review = await post(`/api/sites/${encodeURIComponent(site.id)}/review`, {});
    assert.equal(review.status, 200);
    const reviewed = await review.json();
    assert.equal(reviewed.state, 'reviewed');
    assert.ok(reviewed.last_reviewed_at);

    const updated = await patch(`/api/sites/${encodeURIComponent(site.id)}`, {
      state: 'exclude',
      note: 'Skip this board',
      jobs_url: 'https://careers.example.com/openings',
    });
    assert.equal(updated.status, 200);
    const updatedSite = await updated.json();
    assert.equal(updatedSite.state, 'exclude');
    assert.equal(updatedSite.note, 'Skip this board');
    assert.equal(updatedSite.jobs_url, 'https://careers.example.com/openings');

    const ingested = await post('/site-reviews', {
      site_url: 'https://boards.example.org/jobs',
      site_origin: 'https://boards.example.org',
      page_title: 'Boards Example',
      reviewed_at: '2026-05-31T12:00:00Z',
      next_review_at: '2026-06-07T12:00:00Z',
      note: 'Extension review',
    });
    assert.equal(ingested.status, 200);
    const rows = await (await fetch(`${base}/api/sites`)).json();
    const ingestedSite = rows.find(s => s.origin === 'https://boards.example.org');
    assert.equal(ingestedSite.state, 'reviewed');
    assert.equal(ingestedSite.interval_days, 7);
    assert.equal(ingestedSite.note, 'Extension review');
  });
});
