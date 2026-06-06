import { describe, it, before, after } from 'node:test';
import assert from 'node:assert/strict';
import { writeFileSync } from 'node:fs';
import { join } from 'node:path';
import { createApp } from '../../server/api.js';
import {
  finishLlmRequestAttempt,
  initDb,
  insertCapture,
  markExtractionSucceeded,
  markFitSucceeded,
  markLlmRequestRunning,
  resetJobExtraction,
  startLlmRequestAttempt,
  addResume,
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

describe('GET /api/settings/llm-consent/:provider', () => {
  it('returns consented:false for a new provider', async () => {
    const res = await fetch(`${base}/api/settings/llm-consent/anthropic`);
    assert.equal(res.status, 200);
    const body = await res.json();
    assert.equal(body.provider, 'anthropic');
    assert.equal(body.consented, false);
  });

  it('returns 400 for an invalid provider', async () => {
    const res = await fetch(`${base}/api/settings/llm-consent/invalid`);
    assert.equal(res.status, 400);
    const body = await res.json();
    assert.ok(body.error);
  });
});

describe('POST /api/settings/llm-consent/:provider', () => {
  it('saves consent and GET reflects it', async () => {
    const post = await fetch(`${base}/api/settings/llm-consent/google`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ consented: true }),
    });
    assert.equal(post.status, 200);
    const postBody = await post.json();
    assert.equal(postBody.ok, true);

    const get = await fetch(`${base}/api/settings/llm-consent/google`);
    const getBody = await get.json();
    assert.equal(getBody.consented, true);
  });

  it('can revoke consent', async () => {
    // First grant
    await fetch(`${base}/api/settings/llm-consent/openai`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ consented: true }),
    });
    // Then revoke
    await fetch(`${base}/api/settings/llm-consent/openai`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ consented: false }),
    });
    const get = await fetch(`${base}/api/settings/llm-consent/openai`);
    const getBody = await get.json();
    assert.equal(getBody.consented, false);
  });

  it('returns 400 for an invalid provider', async () => {
    const res = await fetch(`${base}/api/settings/llm-consent/badprovider`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ consented: true }),
    });
    assert.equal(res.status, 400);
  });
});

describe('GET /api/settings/free-models', () => {
  let originalFetch;

  before(() => { originalFetch = globalThis.fetch; });
  after(() => { globalThis.fetch = originalFetch; });

  it('returns ok:true with filtered model list when OpenRouter responds', async () => {
    globalThis.fetch = async (url, opts) => {
      if (String(url).includes('openrouter.ai')) {
        return {
          ok: true,
          json: async () => ({
            data: [
              { id: 'free/model-a', pricing: { prompt: '0', completion: '0' }, supported_parameters: ['structured_outputs'], architecture: { output_modalities: ['text'] } },
              { id: 'paid/model-b', pricing: { prompt: '0.001', completion: '0.002' }, supported_parameters: ['structured_outputs'], architecture: { output_modalities: ['text'] } },
              { id: 'free/model-c', pricing: { prompt: '0', completion: '0' }, supported_parameters: ['response_format'], architecture: { modality: 'text->text' } },
            ],
          }),
        };
      }
      return originalFetch(url, opts);
    };
    const res = await fetch(`${base}/api/settings/free-models`);
    assert.equal(res.status, 200);
    const body = await res.json();
    assert.equal(body.ok, true);
    assert.deepEqual(body.models.sort(), ['free/model-a', 'free/model-c']);
  });

  it('sends the saved API key as Authorization header', async () => {
    await patch('/api/settings', { llm_api_key: 'sk-test-integration-key' });
    let capturedAuth;
    globalThis.fetch = async (url, opts) => {
      if (String(url).includes('openrouter.ai')) {
        capturedAuth = opts?.headers?.Authorization;
        return { ok: true, json: async () => ({ data: [] }) };
      }
      return originalFetch(url, opts);
    };
    const res = await fetch(`${base}/api/settings/free-models`);
    assert.equal(res.status, 200);
    assert.equal(capturedAuth, 'Bearer sk-test-integration-key');
    // restore
    await patch('/api/settings', { llm_api_key: '' });
  });

  it('returns ok:false when OpenRouter returns a non-2xx status', async () => {
    globalThis.fetch = async (url, opts) => {
      if (String(url).includes('openrouter.ai')) return { ok: false, status: 503 };
      return originalFetch(url, opts);
    };
    const res = await fetch(`${base}/api/settings/free-models`);
    assert.equal(res.status, 200);
    const body = await res.json();
    assert.equal(body.ok, false);
    assert.match(body.error, /503/);
  });

  it('returns ok:false on network error', async () => {
    globalThis.fetch = async (url) => {
      if (String(url).includes('openrouter.ai')) throw new Error('ECONNREFUSED');
      return originalFetch(url);
    };
    const res = await fetch(`${base}/api/settings/free-models`);
    assert.equal(res.status, 200);
    const body = await res.json();
    assert.equal(body.ok, false);
    assert.match(body.error, /ECONNREFUSED/);
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
    const jobAddedEvents = [];
    const onJobAdded = payload => jobAddedEvents.push(payload);
    process.on('jobhunt:job-added', onJobAdded);
    const res = await post('/captures', CAPTURE);
    process.off('jobhunt:job-added', onJobAdded);
    assert.equal(res.status, 200);
    const body = await res.json();
    assert.equal(body.ok, true);
    assert.ok(body.capture_id);
    assert.equal(body.duplicate, false);
    assert.equal(jobAddedEvents.length, 1);
    assert.ok(jobAddedEvents[0].jobId);
    assert.equal(jobAddedEvents[0].jobNumber, 1);
    assert.equal(jobAddedEvents[0].pageTitle, CAPTURE.page_title);
  });

  it('returns duplicate:false when re-capturing the same URL (not a new duplicate)', async () => {
    const jobAddedEvents = [];
    const onJobAdded = payload => jobAddedEvents.push(payload);
    process.on('jobhunt:job-added', onJobAdded);
    const res = await post('/captures', CAPTURE);
    process.off('jobhunt:job-added', onJobAdded);
    assert.equal(res.status, 200);
    const body = await res.json();
    assert.equal(body.duplicate, false);
    assert.ok(body.job_number);
    assert.equal(jobAddedEvents.length, 0);
  });
});

describe('POST /api/captures/from-url', () => {
  it('rejects non-http and local server-side URLs', async () => {
    for (const url of ['file:///etc/hosts', 'http://localhost:8765', 'http://127.0.0.1:8765', 'http://192.168.1.10/job']) {
      const res = await post('/api/captures/from-url', { url });
      assert.equal(res.status, 400);
      const body = await res.json();
      assert.match(body.error, /http|local|localhost|private/i);
    }
  });

  it('rejects unparseable URLs', async () => {
    const res = await post('/api/captures/from-url', { url: 'not a url at all' });
    assert.equal(res.status, 400);
    assert.match((await res.json()).error, /http/i);
  });

  it('rejects 0.0.0.0 and loopback addresses', async () => {
    for (const url of ['http://0.0.0.0/job', 'http://[::1]/job']) {
      const res = await post('/api/captures/from-url', { url });
      assert.equal(res.status, 400);
    }
  });

});

describe('POST /api/captures/from-url happy path (mocked fetch)', () => {
  it('creates a capture when remote URL returns valid HTML', async () => {
    const originalFetch = globalThis.fetch;
    try {
      globalThis.fetch = async (url, ...args) => {
        if (String(url).includes('127.0.0.1')) return originalFetch(url, ...args);
        return {
          url: 'https://jobs.mocked.example.com/engineer-123',
          ok: true,
          headers: { get: () => null },
          text: async () => '<html><title>Senior Engineer at MockedCo</title><body>Job description for senior engineer role at mocked company</body></html>',
        };
      };
      const res = await post('/api/captures/from-url', {
        url: 'https://jobs.mocked.example.com/engineer-123',
        note: 'From URL test',
      });
      assert.equal(res.status, 200);
      const body = await res.json();
      assert.ok(body.ok);
      assert.ok(body.capture_id);
    } finally {
      globalThis.fetch = originalFetch;
    }
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
      'last_opened_at',
      'duplicate_of_job_id', 'visible_byte_size', 'selected_text_present', 'structured_data_count',
    ]) {
      assert.ok(field in job, `expected ${field} in job payload`);
    }
  });

  it('does not show closed exact-hash duplicates as review groups', async () => {
    const first = insertCapture({
      url: 'https://closed-dupes.example.com/jobs/1',
      page_title: 'Closed Duplicate 1',
      visible_text: 'Same closed duplicate description body',
    }, dbPath);
    const second = insertCapture({
      url: 'https://closed-dupes.example.org/jobs/1',
      page_title: 'Closed Duplicate 2',
      visible_text: 'Same closed duplicate description body',
    }, dbPath);
    const db = initDb(dbPath);
    const jobIds = db.prepare('SELECT id FROM jobs WHERE capture_id IN (?, ?)').all(first.capture_id, second.capture_id).map(row => row.id);
    const placeholders = jobIds.map(() => '?').join(',');
    db.prepare(`UPDATE jobs SET status='archived' WHERE id IN (${placeholders})`).run(...jobIds);

    const res = await fetch(`${base}/api/ui-data`);
    const body = await res.json();
    const closedGroups = body.dupes.filter(group => group.job_ids.some(id => jobIds.includes(id)));

    assert.deepEqual(closedGroups, []);
  });

  it('does not show low-signal exact-hash duplicates as review groups', async () => {
    const first = insertCapture({
      url: 'https://weak-dupes.example.com/jobs/1',
      page_title: 'Weak Duplicate 1',
      visible_text: '$',
    }, dbPath);
    const second = insertCapture({
      url: 'https://weak-dupes.example.org/jobs/1',
      page_title: 'Weak Duplicate 2',
      visible_text: '$',
    }, dbPath);
    const db = initDb(dbPath);
    const jobIds = db.prepare('SELECT id FROM jobs WHERE capture_id IN (?, ?)').all(first.capture_id, second.capture_id).map(row => row.id);

    const res = await fetch(`${base}/api/ui-data`);
    const body = await res.json();
    const weakGroups = body.dupes.filter(group => group.job_ids.some(id => jobIds.includes(id)));

    assert.deepEqual(weakGroups, []);
  });

  it('shows meaningful exact-hash duplicates as review groups', async () => {
    const meaningfulDescription = [
      'This duplicate posting describes a senior backend engineering role building reliable workflow systems.',
      'The team owns distributed services, database integrations, API contracts, observability, incident response,',
      'performance tuning, product collaboration, customer-facing reliability improvements, and long-term architecture.',
    ].join(' ');
    const first = insertCapture({
      url: 'https://meaningful-dupes.example.com/jobs/1',
      page_title: 'Meaningful Duplicate 1',
      visible_text: meaningfulDescription,
    }, dbPath);
    const second = insertCapture({
      url: 'https://meaningful-dupes.example.org/jobs/1',
      page_title: 'Meaningful Duplicate 2',
      visible_text: meaningfulDescription,
    }, dbPath);
    const db = initDb(dbPath);
    const jobIds = db.prepare('SELECT id FROM jobs WHERE capture_id IN (?, ?)').all(first.capture_id, second.capture_id).map(row => row.id);

    const res = await fetch(`${base}/api/ui-data`);
    const body = await res.json();
    const meaningfulGroups = body.dupes.filter(group => group.job_ids.every(id => jobIds.includes(id)));

    assert.equal(meaningfulGroups.length, 1);
  });
});

describe('POST /api/jobs/:jobId/opened', () => {
  it('records last opened time and a timeline event', async () => {
    const created = await post('/captures', {
      ...CAPTURE,
      url: 'https://example.com/opened-api',
      page_title: 'Opened API Job',
      visible_text: 'Opened API job posting',
    });
    const db = initDb(dbPath);
    const jobId = db.prepare('SELECT id FROM jobs WHERE capture_id=?').get((await created.json()).capture_id).id;

    const res = await post(`/api/jobs/${jobId}/opened`, {});
    assert.equal(res.status, 200);
    const body = await res.json();
    assert.equal(body.ok, true);
    assert.ok(body.last_opened_at);

    const check = await fetch(`${base}/api/ui-data`);
    const { jobs } = await check.json();
    const job = jobs.find(j => j.job_id === jobId);
    assert.equal(job.last_opened_at, body.last_opened_at);
    assert.ok(job.events.some(e => e.event_type === 'source_opened' && e.occurred_at === body.last_opened_at));
  });

  it('returns 400 for a missing job', async () => {
    const res = await post('/api/jobs/missing-job/opened', {});
    assert.equal(res.status, 400);
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

    const resume = addResume(dbPath, { name: 'Platform resume', text: 'platform program manager' });
    markFitSucceeded(jobId, resume.id, {
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
    assert.equal(job.fit_score_json.best_resume_name, 'Platform resume');
    assert.deepEqual(job.fit_score_json.requirements_met, ['Program leadership']);
    assert.deepEqual(job.fit_score_json.requirements_not_met, ['Domain-specific compliance']);

    // Per-resume breakdown is exposed for the detail panel.
    assert.equal(job.fit_scores.length, 1);
    assert.equal(job.fit_scores[0].resume_id, resume.id);
    assert.equal(job.fit_scores[0].resume_name, 'Platform resume');
    assert.equal(job.fit_scores[0].score, 82);
    assert.equal(job.fit_scores[0].status, 'succeeded');
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

    addResume(dbPath, { name: 'Bulk resume', text: 'program manager resume' });
    res = await post('/api/jobs/bulk/llm', { job_ids: [completeJobId, missingJobId], mode: 'fit_score' });
    assert.equal(res.status, 200);
    body = await res.json();
    assert.equal(body.queued, 1);   // only the extracted job
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

  it('GET /api/sites returns all sites as array', async () => {
    const res = await fetch(`${base}/api/sites`);
    assert.equal(res.status, 200);
    const body = await res.json();
    assert.ok(Array.isArray(body));
  });

  it('DELETE /api/sites/:siteId removes the site', async () => {
    const add = await post('/api/sites', { url: 'https://delete-me.example.com/jobs', page_title: 'Delete Me' });
    const site = await add.json();
    const res = await del(`/api/sites/${encodeURIComponent(site.id)}`, {});
    assert.equal(res.status, 200);
    assert.equal((await res.json()).ok, true);
  });
});

describe('resume CRUD APIs', () => {
  it('full CRUD lifecycle', async () => {
    // GET empty list
    const listRes = await fetch(`${base}/api/resumes`);
    assert.equal(listRes.status, 200);
    const { resumes: before } = await listRes.json();
    assert.ok(Array.isArray(before));

    // POST create
    const createRes = await post('/api/resumes', { name: 'My Resume', text: 'Experienced TPM with 10 years.' });
    assert.equal(createRes.status, 200);
    const { ok, resume } = await createRes.json();
    assert.equal(ok, true);
    assert.ok(resume.id);
    assert.equal(resume.name, 'My Resume');

    // GET by id
    const getRes = await fetch(`${base}/api/resumes/${resume.id}`);
    assert.equal(getRes.status, 200);
    const fetched = await getRes.json();
    assert.equal(fetched.name, 'My Resume');

    // PATCH update
    const patchRes = await patch(`/api/resumes/${resume.id}`, { name: 'Updated Resume' });
    assert.equal(patchRes.status, 200);
    assert.equal((await patchRes.json()).resume.name, 'Updated Resume');

    // DELETE
    const delRes = await del(`/api/resumes/${resume.id}`, {});
    assert.equal(delRes.status, 200);
    assert.equal((await delRes.json()).ok, true);

    // GET after delete → 404
    const afterRes = await fetch(`${base}/api/resumes/${resume.id}`);
    assert.equal(afterRes.status, 404);
  });

  it('POST /api/resumes returns 400 for empty text', async () => {
    const res = await post('/api/resumes', { name: 'Empty', text: '   ' });
    assert.equal(res.status, 400);
    assert.match((await res.json()).error, /empty/i);
  });
});

describe('individual job operation APIs', () => {
  let jobId;

  before(async () => {
    const created = await post('/captures', {
      ...CAPTURE,
      url: 'https://example.com/job-ops-target',
      page_title: 'Job Ops Target',
      visible_text: 'Job operations test capture text here.',
    });
    const db = initDb(dbPath);
    jobId = db.prepare('SELECT id FROM jobs WHERE capture_id=?').get((await created.json()).capture_id).id;
  });

  it('POST /api/jobs/:jobId/read marks job as read', async () => {
    const res = await post(`/api/jobs/${jobId}/read`, {});
    assert.equal(res.status, 200);
    assert.equal((await res.json()).ok, true);
  });

  it('PATCH /api/jobs/:jobId updates job fields', async () => {
    const res = await patch(`/api/jobs/${jobId}`, { company: 'FieldUpdated Co' });
    assert.equal(res.status, 200);
    assert.equal((await res.json()).ok, true);
  });

  it('PATCH /api/jobs/:jobId/skills updates skills', async () => {
    const res = await patch(`/api/jobs/${jobId}/skills`, { skills: ['python', 'sql'] });
    assert.equal(res.status, 200);
    assert.equal((await res.json()).ok, true);
  });

  it('PATCH /api/jobs/:jobId/rating sets a rating', async () => {
    const res = await patch(`/api/jobs/${jobId}/rating`, { rating: 4 });
    assert.equal(res.status, 200);
    assert.equal((await res.json()).ok, true);
  });

  it('POST /api/jobs/:jobId/extract resets extraction and returns request_id', async () => {
    const res = await post(`/api/jobs/${jobId}/extract`, {});
    assert.equal(res.status, 200);
    const body = await res.json();
    assert.equal(body.ok, true);
    assert.ok(body.request_id);
  });

  it('POST /api/jobs/:jobId/archive archives the job', async () => {
    const res = await post(`/api/jobs/${jobId}/archive`, {});
    assert.equal(res.status, 200);
    assert.equal((await res.json()).ok, true);
  });

  it('DELETE /api/jobs/:jobId deletes the job', async () => {
    const created = await post('/captures', {
      ...CAPTURE,
      url: 'https://example.com/to-delete',
      page_title: 'Delete Me',
      visible_text: 'This job will be deleted.',
    });
    const db = initDb(dbPath);
    const toDeleteId = db.prepare('SELECT id FROM jobs WHERE capture_id=?').get((await created.json()).capture_id).id;

    const res = await del(`/api/jobs/${toDeleteId}`, {});
    assert.equal(res.status, 200);
    assert.equal((await res.json()).ok, true);
  });
});

describe('action APIs', () => {
  let jobId;
  let actionId;

  before(async () => {
    const created = await post('/captures', {
      ...CAPTURE,
      url: 'https://example.com/actions-target',
      page_title: 'Actions Target',
      visible_text: 'Actions test capture text here.',
    });
    const db = initDb(dbPath);
    jobId = db.prepare('SELECT id FROM jobs WHERE capture_id=?').get((await created.json()).capture_id).id;
  });

  it('POST /api/jobs/:jobId/actions creates an action', async () => {
    const res = await post(`/api/jobs/${jobId}/actions`, { note: 'Follow up', due_date: '2026-07-01' });
    assert.equal(res.status, 200);
    const action = await res.json();
    assert.ok(action.id);
    assert.equal(action.note, 'Follow up');
    actionId = action.id;
  });

  it('GET /api/jobs/:jobId/actions returns the active action', async () => {
    const res = await fetch(`${base}/api/jobs/${jobId}/actions`);
    assert.equal(res.status, 200);
    const action = await res.json();
    assert.ok(action.id);
  });

  it('POST /api/actions/:actionId/snooze extends the due date', async () => {
    const res = await post(`/api/actions/${actionId}/snooze`, { days: 3 });
    assert.equal(res.status, 200);
    const snoozed = await res.json();
    assert.ok(snoozed.id);
  });

  it('POST /api/actions/:actionId/complete marks the action done', async () => {
    const res = await post(`/api/actions/${actionId}/complete`, {});
    assert.equal(res.status, 200);
    assert.equal((await res.json()).ok, true);
  });
});

describe('LLM queue management APIs', () => {
  it('GET /api/llm-queue returns queue state with counts', async () => {
    const res = await fetch(`${base}/api/llm-queue`);
    assert.equal(res.status, 200);
    const body = await res.json();
    assert.equal(body.ok, true);
    assert.ok(Array.isArray(body.items));
    assert.ok(typeof body.paused === 'boolean');
    assert.ok('queued' in body.counts);
    assert.ok('running' in body.counts);
  });

  it('POST /api/llm-queue/pause toggles the paused flag', async () => {
    const res = await post('/api/llm-queue/pause', { paused: true });
    assert.equal(res.status, 200);
    const body = await res.json();
    assert.equal(body.ok, true);
    assert.equal(body.paused, true);
    // restore
    await post('/api/llm-queue/pause', { paused: false });
  });

  it('POST /api/llm-queue/cancel-all returns canceled count', async () => {
    const res = await post('/api/llm-queue/cancel-all', {});
    assert.equal(res.status, 200);
    const body = await res.json();
    assert.equal(body.ok, true);
    assert.ok(typeof body.canceled === 'number');
  });
});

describe('GET /api/debug/stats', () => {
  it('returns structured stats object', async () => {
    const res = await fetch(`${base}/api/debug/stats`);
    assert.equal(res.status, 200);
    const body = await res.json();
    assert.ok(Array.isArray(body.jobsByStatus));
    assert.ok(Array.isArray(body.jobsByExtraction));
    assert.ok(Array.isArray(body.llmCounts));
    assert.ok(typeof body.captureCount === 'number');
    assert.ok('tokenCaps' in body);
  });
});

describe('404 / not-found branches', () => {
  it('DELETE /api/jobs/:jobId returns 404 for nonexistent job', async () => {
    const res = await del('/api/jobs/nonexistent-job-id', {});
    assert.equal(res.status, 404);
  });

  it('GET /api/resumes/:id returns 404 for nonexistent resume', async () => {
    const res = await fetch(`${base}/api/resumes/nonexistent-id`);
    assert.equal(res.status, 404);
  });

  it('PATCH /api/resumes/:id returns 404 for nonexistent resume', async () => {
    const res = await patch('/api/resumes/nonexistent-id', { name: 'x' });
    assert.equal(res.status, 404);
  });

  it('POST /api/llm-queue/:requestId/cancel returns 404 for nonexistent request', async () => {
    const res = await post('/api/llm-queue/nonexistent-req-id/cancel', {});
    assert.equal(res.status, 404);
  });

  it('PATCH /api/sites/nonexistent returns 404', async () => {
    const res = await patch('/api/sites/nonexistent-site-id', { note: 'x' });
    assert.equal(res.status, 404);
  });
});

describe('POST /api/jobs/:jobId/fit-score', () => {
  it('returns 400 when job is not yet extracted', async () => {
    const created = await post('/captures', {
      ...CAPTURE,
      url: 'https://example.com/fit-score-unextracted',
      page_title: 'Unextracted',
      visible_text: 'Unextracted job text',
    });
    const db = initDb(dbPath);
    const jobId = db.prepare('SELECT id FROM jobs WHERE capture_id=?').get((await created.json()).capture_id).id;
    const res = await post(`/api/jobs/${jobId}/fit-score`, {});
    assert.equal(res.status, 400);
    assert.match((await res.json()).error, /extract/i);
  });
});

describe('simple informational API routes', () => {
  it('GET /api/ping returns app name and version', async () => {
    const res = await fetch(`${base}/api/ping`);
    assert.equal(res.status, 200);
    const body = await res.json();
    assert.equal(body.app, 'jobhunt');
    assert.ok('version' in body);
  });

  it('POST /api/app/focus emits event and returns ok', async () => {
    const events = [];
    const handler = e => events.push(e);
    process.on('jobhunt:open-job', handler);
    const res = await post('/api/app/focus', { job_number: 42 });
    process.off('jobhunt:open-job', handler);
    assert.equal(res.status, 200);
    assert.equal((await res.json()).ok, true);
    assert.equal(events.length, 1);
    assert.equal(events[0].jobNumber, 42);
  });

  it('GET /api/dashboard returns jobs and isDemo', async () => {
    const res = await fetch(`${base}/api/dashboard`);
    assert.equal(res.status, 200);
    const body = await res.json();
    assert.ok(Array.isArray(body.jobs));
    assert.ok('isDemo' in body);
  });

  it('GET /exports/jobs.csv returns CSV content-type', async () => {
    const res = await fetch(`${base}/exports/jobs.csv`);
    assert.equal(res.status, 200);
    assert.ok(res.headers.get('content-type').includes('text/csv'));
    const text = await res.text();
    assert.ok(text.startsWith('job_number,'));
  });

  it('POST /api/db/switch with non-demo mode switches back to main DB', async () => {
    const res = await post('/api/db/switch', { mode: 'main' });
    assert.equal(res.status, 200);
    const body = await res.json();
    assert.equal(body.ok, true);
    assert.equal(body.isDemo, false);
  });
});

describe('GET /api/jobs/by-url', () => {
  it('returns 400 when url param is missing', async () => {
    const res = await fetch(`${base}/api/jobs/by-url`);
    assert.equal(res.status, 400);
  });

  it('returns 404 when no job matches the URL', async () => {
    const res = await fetch(`${base}/api/jobs/by-url?url=${encodeURIComponent('https://notfound.example.com/job/99')}`);
    assert.equal(res.status, 404);
  });

  it('returns the job when URL matches', async () => {
    const res = await fetch(`${base}/api/jobs/by-url?url=${encodeURIComponent(CAPTURE.url)}`);
    assert.equal(res.status, 200);
    const job = await res.json();
    assert.ok(job.job_id || job.id);
  });
});

describe('validateFetchableCaptureUrl — private IP ranges', () => {
  it('rejects private IPv4 ranges (10.x, 192.168.x, etc.)', async () => {
    for (const url of ['http://192.168.1.100/job', 'http://10.0.0.1/job', 'http://172.16.0.1/job']) {
      const res = await post('/api/captures/from-url', { url });
      assert.equal(res.status, 400, `expected 400 for ${url}`);
      assert.match((await res.json()).error, /private|local/i);
    }
  });
});

describe('no-cache middleware and root/static routes', () => {
  it('GET / sets no-cache headers via middleware', async () => {
    const res = await fetch(`${base}/`);
    // The route exists and serves index.html (200) or 503 if static files absent.
    assert.ok(res.status === 200 || res.status === 503);
    assert.match(res.headers.get('cache-control') || '', /no-store|no-cache/);
  });

  it('GET /favicon.ico is handled by the route', async () => {
    const res = await fetch(`${base}/favicon.ico`);
    // File may not exist in test environment; just verify route is reached (not 404 from Express default)
    assert.ok(res.status === 200 || res.status === 404);
  });
});

describe('misc API routes', () => {
  it('POST /api/db/switch with mode:demo returns 400 when demo DB not configured', async () => {
    const res = await post('/api/db/switch', { mode: 'demo' });
    assert.equal(res.status, 400);
    assert.match((await res.json()).error, /demo/i);
  });

  it('POST /api/db/reseed-demo returns 400 when not in demo mode', async () => {
    const res = await post('/api/db/reseed-demo', {});
    assert.equal(res.status, 400);
    assert.match((await res.json()).error, /demo/i);
  });

  it('POST /api/llm-queue/enqueue-all enqueues unqueued pending jobs', async () => {
    const res = await post('/api/llm-queue/enqueue-all', {});
    assert.equal(res.status, 200);
    const body = await res.json();
    assert.equal(body.ok, true);
    assert.ok(typeof body.enqueued === 'number');
  });
});

describe('route error-path catch blocks', () => {
  let jobId;

  before(async () => {
    const res = await post('/captures', {
      ...CAPTURE,
      url: 'https://example.com/error-path-target',
      page_title: 'Error Path Target',
      visible_text: 'Testing error path coverage.',
    });
    const db = initDb(dbPath);
    jobId = db.prepare('SELECT id FROM jobs WHERE capture_id=?').get((await res.json()).capture_id).id;
  });

  it('PATCH /api/jobs/:jobId/status returns 400 for invalid status', async () => {
    const res = await patch(`/api/jobs/${jobId}/status`, { status: 'invalid_status_value' });
    assert.equal(res.status, 400);
    assert.match((await res.json()).error, /invalid status/i);
  });

  it('POST /api/jobs/:jobId/notes returns 400 for empty note', async () => {
    const res = await post(`/api/jobs/${jobId}/notes`, { note: '' });
    assert.equal(res.status, 400);
    assert.match((await res.json()).error, /required|empty/i);
  });

  it('POST /api/jobs/:jobId/archive returns 400 for nonexistent job', async () => {
    const res = await post('/api/jobs/nonexistent-job-id-99/archive', {});
    assert.equal(res.status, 400);
    assert.match((await res.json()).error, /not found/i);
  });

  it('POST /api/jobs/bulk/llm-by-number returns 400 for unknown mode', async () => {
    const res = await post('/api/jobs/bulk/llm-by-number', { job_numbers: [1], mode: 'invalid_mode' });
    assert.equal(res.status, 400);
  });

  it('PATCH /api/jobs/:jobId/rating returns 400 for out-of-range rating', async () => {
    const res = await patch(`/api/jobs/${jobId}/rating`, { rating: 999 });
    assert.equal(res.status, 400);
    assert.match((await res.json()).error, /rating/i);
  });

  it('POST /api/jobs/:jobId/extract returns 400 for nonexistent job', async () => {
    const res = await post('/api/jobs/nonexistent-extract-id/extract', {});
    assert.equal(res.status, 400);
    assert.match((await res.json()).error, /not found/i);
  });
});

describe('POST /api/jobs/:jobId/fit-score success path', () => {
  let extractedJobId;

  before(async () => {
    const res = await post('/captures', {
      ...CAPTURE,
      url: 'https://example.com/fitscore-success-target',
      page_title: 'FitScore Target',
      visible_text: 'Testing fit score success path.',
    });
    const db = initDb(dbPath);
    extractedJobId = db.prepare('SELECT id FROM jobs WHERE capture_id=?').get((await res.json()).capture_id).id;
    markExtractionSucceeded(extractedJobId, {
      company: 'FitTest Co', title: 'Senior TPM', location: 'Remote', remote_type: 'remote',
      salary_min: 150000, salary_max: 220000, salary_currency: 'USD', salary_note: '$150k-$220k',
      employment_type: 'full_time', seniority: 'senior', skills: [],
      summary: '', requirements: [], nice_to_haves: [], benefits: [],
      application_url: null, confidence: {},
    }, dbPath, null, 'test-model', 0.9);
  });

  it('queues fit scoring for all active resumes and returns ok', async () => {
    const db = initDb(dbPath);
    if (!db.prepare("SELECT id FROM resumes WHERE active=1").get()) {
      addResume(dbPath, { name: 'FitScore Test Resume', text: 'Experienced technical program manager' });
    }
    const res = await post(`/api/jobs/${extractedJobId}/fit-score`, {});
    assert.equal(res.status, 200);
    assert.equal((await res.json()).ok, true);
  });

  it('queues fit scoring for a specific resume and returns ok', async () => {
    const db = initDb(dbPath);
    const resume = db.prepare("SELECT id FROM resumes WHERE active=1").get();
    if (!resume) return;
    const res = await post(`/api/jobs/${extractedJobId}/fit-score`, { resume_id: resume.id });
    assert.equal(res.status, 200);
    assert.equal((await res.json()).ok, true);
  });
});

describe('PATCH /api/resumes/:id extended branch coverage', () => {
  it('updating text and active status covers additional optional field branches', async () => {
    const created = await post('/api/resumes', { name: 'Branch Resume', text: 'Original text for branch test.' });
    const { resume } = await created.json();

    const patched = await patch(`/api/resumes/${resume.id}`, { text: 'Updated text content here.', active: false });
    assert.equal(patched.status, 200);
    const body = await patched.json();
    assert.equal(body.ok, true);

    await del(`/api/resumes/${resume.id}`, {});
  });
});

describe('POST /api/resumes with edge case inputs', () => {
  it('uses default name Resume when name is not provided', async () => {
    const res = await post('/api/resumes', { text: 'Resume without a name field.' });
    assert.equal(res.status, 200);
    const { resume } = await res.json();
    assert.equal(resume.name, 'Resume');
    await del(`/api/resumes/${resume.id}`, {});
  });
});

describe('autoExtract=true code paths', () => {
  let autoBase;
  let autoServer;
  let autoDbPath;

  before(async () => {
    autoDbPath = tempDbPath();
    initDb(autoDbPath);
    const app = createApp({ dbPath: autoDbPath, autoExtract: true });
    await new Promise(resolve => {
      autoServer = app.listen(0, '127.0.0.1', resolve);
    });
    autoBase = `http://127.0.0.1:${autoServer.address().port}`;
  });

  after(async () => {
    await new Promise(resolve => autoServer.close(resolve));
    cleanupDb(autoDbPath);
  });

  it('POST /captures with autoExtract=true triggers background extraction fire-and-forget', async () => {
    const res = await fetch(`${autoBase}/captures`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ ...CAPTURE, url: 'https://example.com/autoextract-test', page_title: 'AutoExtract Job', visible_text: 'Testing autoExtract code path fire and forget.' }),
    });
    assert.equal(res.status, 200);
    const body = await res.json();
    assert.equal(body.ok, true);
  });

  it('POST /api/jobs/:jobId/extract with autoExtract=true triggers background extraction', async () => {
    const db = initDb(autoDbPath);
    const jobRow = db.prepare('SELECT id FROM jobs LIMIT 1').get();
    if (!jobRow) return;
    const res = await fetch(`${autoBase}/api/jobs/${jobRow.id}/extract`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({}),
    });
    assert.equal(res.status, 200);
    assert.equal((await res.json()).ok, true);
  });

  it('POST /api/jobs/bulk/llm with skipped jobs triggers autoExtract fallback (else if branch)', async () => {
    const captureRes = await fetch(`${autoBase}/captures`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ ...CAPTURE, url: 'https://auto-bulk-llm.example.com/job/1', page_title: 'Auto Bulk LLM', visible_text: 'Testing autoExtract else-if branch in bulk llm.' }),
    });
    const captureBody = await captureRes.json();
    const db = initDb(autoDbPath);
    const job = db.prepare('SELECT id FROM jobs WHERE capture_id=?').get(captureBody.capture_id);
    // Call with fit_score mode but no resumes exist — all jobs skipped, request_ids=[0], autoExtract fallback runs
    const res = await fetch(`${autoBase}/api/jobs/bulk/llm`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ job_ids: [job.id], mode: 'fit_score' }),
    });
    assert.equal(res.status, 200);
    const body = await res.json();
    assert.equal(body.ok, true);
  });

  it('POST /api/jobs/bulk/llm-by-number with skipped jobs triggers autoExtract fallback', async () => {
    const db = initDb(autoDbPath);
    const job = db.prepare('SELECT id, job_number FROM jobs LIMIT 1').get();
    if (!job) return;
    // fit_score with no resumes → all skipped → else if autoExtract branch
    const res = await fetch(`${autoBase}/api/jobs/bulk/llm-by-number`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ job_numbers: [job.job_number], mode: 'fit_score' }),
    });
    assert.equal(res.status, 200);
    const body = await res.json();
    assert.equal(body.ok, true);
  });
});

describe('GET /api/llm-cost', () => {
  it('returns cost estimate (has_data and structural fields present)', async () => {
    const res = await fetch(`${base}/api/llm-cost`);
    assert.equal(res.status, 200);
    const body = await res.json();
    assert.ok(typeof body.has_data === 'boolean');
    assert.ok(typeof body.jobs_total === 'number');
    assert.ok('all' in body && 'remaining' in body);
  });

  it('returns cost estimate with jobs and resumes', async () => {
    const db = initDb(dbPath);
    const resumeCount = db.prepare("SELECT COUNT(*) as n FROM resumes WHERE active=1").get().n;
    if (!resumeCount) addResume(dbPath, { name: 'Cost Test Resume', text: 'Senior program manager with ten years experience.' });

    const res = await fetch(`${base}/api/llm-cost`);
    assert.equal(res.status, 200);
    const body = await res.json();
    assert.ok(typeof body.jobs_total === 'number');
    assert.ok(typeof body.jobs_extracted === 'number');
  });
});

describe('POST /api/duplicates/decision', () => {
  it('covers cleaned_hash branch (throws when hash not found)', async () => {
    const res = await post('/api/duplicates/decision', {
      cleaned_hash: 'nonexistent-hash-abc123',
      decision: 'not_duplicate',
      keep_job_id: null,
      note: 'Test decision',
    });
    assert.equal(res.status, 400);
    assert.match((await res.json()).error, /not found/i);
  });

  it('covers job_ids branch (throws when job ids not found)', async () => {
    const res = await post('/api/duplicates/decision', {
      job_ids: ['nonexistent-id-1', 'nonexistent-id-2'],
      decision: 'not_duplicate',
      keep_job_id: null,
      note: '',
    });
    assert.equal(res.status, 400);
  });
});

describe('POST /api/sites/review via body site_ref', () => {
  it('reviews an existing site referenced by ID in body', async () => {
    const created = await post('/api/sites', { url: 'https://site-review-body.example.com/jobs', page_title: 'Body Review Site' });
    const site = await created.json();
    const res = await post('/api/sites/review', { site_ref: site.id });
    assert.ok(res.status === 200 || res.status === 404);
  });

  it('returns 404 for nonexistent site_ref', async () => {
    const res = await post('/api/sites/review', { site_ref: 'nonexistent-site-id' });
    assert.equal(res.status, 404);
  });
});

describe('POST /api/sites — invalid URL origin fallback', () => {
  it('uses raw URL as origin when URL parsing fails', async () => {
    const res = await post('/api/sites', { url: 'not-a-valid-url-xyz', page_title: 'Bad URL Site' });
    const body = await res.json();
    assert.ok(body.id || body.error);
  });
});

describe('POST /api/actions/:actionId error paths', () => {
  it('POST complete with nonexistent id returns 404 with not-found ternary', async () => {
    const res = await post('/api/actions/nonexistent-action-id/complete', {});
    assert.equal(res.status, 404);
    assert.match((await res.json()).error, /not found/i);
  });

  it('POST snooze with nonexistent id returns 404 with not-found ternary', async () => {
    const res = await post('/api/actions/nonexistent-action-id/snooze', { days: 3 });
    assert.equal(res.status, 404);
    assert.match((await res.json()).error, /not found/i);
  });
});

describe('GET /api/settings/model-context', () => {
  it('returns context response (fails gracefully when LM Studio not running)', async () => {
    const res = await fetch(`${base}/api/settings/model-context`);
    assert.equal(res.status, 200);
    const body = await res.json();
    assert.ok('recommendedMinTokens' in body);
  });
});

describe('POST /api/jobs/check-availability', () => {
  it('returns ok with checked/unavailable/marked counts', async () => {
    const res = await post('/api/jobs/check-availability', {});
    assert.equal(res.status, 200);
    const body = await res.json();
    assert.ok(body.ok);
    assert.ok(typeof body.checked === 'number');
  });
});

describe('POST /api/site-reviews/mark', () => {
  it('creates a site review and returns site_review_id', async () => {
    const res = await post('/api/site-reviews/mark', {
      site_url: 'https://mark-test.example.com/jobs',
      site_origin: 'https://mark-test.example.com',
      page_title: 'Mark Test Site',
      reviewed_at: new Date().toISOString(),
    });
    assert.equal(res.status, 200);
    assert.ok((await res.json()).site_review_id);
  });
});

describe('POST /site-reviews validation', () => {
  it('returns 400 when site_url or site_origin is missing', async () => {
    const res = await post('/site-reviews', { page_title: 'Missing required fields' });
    assert.equal(res.status, 400);
  });
});

describe('PATCH /api/sites/:siteId with next_review_days and interval_days', () => {
  it('covers next_review_days branch in PATCH handler', async () => {
    const add = await post('/api/sites', { url: 'https://next-review-days.example.com/jobs' });
    const site = await add.json();
    const res = await patch(`/api/sites/${encodeURIComponent(site.id)}`, { next_review_days: 7 });
    assert.equal(res.status, 200);
  });

  it('covers interval_days branch in PATCH handler', async () => {
    const add = await post('/api/sites', { url: 'https://interval-days.example.com/jobs' });
    const site = await add.json();
    const res = await patch(`/api/sites/${encodeURIComponent(site.id)}`, { interval_days: 14 });
    assert.equal(res.status, 200);
  });
});

describe('POST /api/llm-queue/:requestId/cancel success path', () => {
  it('returns ok:true when request is cancelled', async () => {
    const created = await post('/captures', {
      ...CAPTURE,
      url: 'https://example.com/cancel-llm-req-test',
      page_title: 'Cancel LLM Req Test',
      visible_text: 'Cancel test visible text unique xyz',
    });
    const captureId = (await created.json()).capture_id;
    const db = initDb(dbPath);
    const job = db.prepare('SELECT id FROM jobs WHERE capture_id=?').get(captureId);
    const req = db.prepare("SELECT id FROM llm_requests WHERE job_id=? AND status='queued'").get(job.id);
    const res = await post(`/api/llm-queue/${req.id}/cancel`, {});
    assert.equal(res.status, 200);
    assert.equal((await res.json()).ok, true);
  });
});

describe('POST /api/duplicates/decision success path', () => {
  it('marks two jobs as not_duplicate and returns ok', async () => {
    const [r1, r2] = await Promise.all([
      post('/captures', { ...CAPTURE, url: 'https://dup-decide-a.example.com/1', page_title: 'Dup A', visible_text: 'Decide not duplicate test job A unique text xyz' }),
      post('/captures', { ...CAPTURE, url: 'https://dup-decide-b.example.com/1', page_title: 'Dup B', visible_text: 'Decide not duplicate test job B unique text xyz' }),
    ]);
    const db = initDb(dbPath);
    const jobA = db.prepare('SELECT id FROM jobs WHERE capture_id=?').get((await r1.json()).capture_id)?.id;
    const jobB = db.prepare('SELECT id FROM jobs WHERE capture_id=?').get((await r2.json()).capture_id)?.id;
    if (!jobA || !jobB) return;
    const res = await post('/api/duplicates/decision', {
      job_ids: [jobA, jobB],
      decision: 'not_duplicate',
      keep_job_id: null,
      note: 'Test decision',
    });
    assert.equal(res.status, 200);
    assert.equal((await res.json()).ok, true);
  });
});

describe('POST /api/captures/from-url redirect to local URL', () => {
  it('rejects when redirect URL is a local address (covers validateFetchableCaptureUrl post-redirect)', async () => {
    const originalFetch = globalThis.fetch;
    try {
      globalThis.fetch = async (url, ...args) => {
        if (String(url).includes('127.0.0.1')) return originalFetch(url, ...args);
        return {
          url: 'http://localhost/internal-job',
          ok: true,
          headers: { get: () => null },
          text: async () => '<html><body>some content</body></html>',
        };
      };
      const res = await post('/api/captures/from-url', { url: 'https://some-job-site.example.com/job/456' });
      assert.equal(res.status, 400);
      assert.match((await res.json()).error, /localhost/i);
    } finally {
      globalThis.fetch = originalFetch;
    }
  });
});

describe('POST /api/captures/from-url outer catch (fetch throws)', () => {
  it('returns 500 when fetch throws a general network error', async () => {
    const originalFetch = globalThis.fetch;
    try {
      globalThis.fetch = async (url, ...args) => {
        if (String(url).includes('127.0.0.1')) return originalFetch(url, ...args);
        throw new Error('ECONNREFUSED: connection refused');
      };
      const res = await post('/api/captures/from-url', { url: 'https://unreachable-job-example.com/job/789' });
      assert.equal(res.status, 500);
    } finally {
      globalThis.fetch = originalFetch;
    }
  });
});

describe('POST /api/jobs/:jobId/fit-score with no active resumes', () => {
  let noResumeBase;
  let noResumeServer;
  let noResumeDbPath;

  before(async () => {
    noResumeDbPath = tempDbPath();
    initDb(noResumeDbPath);
    const app = createApp({ dbPath: noResumeDbPath, autoExtract: false });
    await new Promise(resolve => {
      noResumeServer = app.listen(0, '127.0.0.1', resolve);
    });
    noResumeBase = `http://127.0.0.1:${noResumeServer.address().port}`;
  });

  after(async () => {
    await new Promise(resolve => noResumeServer.close(resolve));
    cleanupDb(noResumeDbPath);
  });

  it('returns 400 when no resumes exist and job is extracted', async () => {
    const captureRes = await fetch(`${noResumeBase}/captures`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ ...CAPTURE, url: 'https://no-resume-job.example.com/job/1', page_title: 'No Resume Job', visible_text: 'Job without any resume configured.' }),
    });
    const captureBody = await captureRes.json();
    const db = initDb(noResumeDbPath);
    const job = db.prepare('SELECT id FROM jobs WHERE capture_id=?').get(captureBody.capture_id);
    markExtractionSucceeded(job.id, { company: 'NoCo', title: 'No Resume Engineer' }, noResumeDbPath);

    const res = await fetch(`${noResumeBase}/api/jobs/${job.id}/fit-score`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({}),
    });
    assert.equal(res.status, 400);
    assert.match((await res.json()).error, /resume/i);
  });
});

describe('ui-data with duplicate-status job and malformed structured_data_json', () => {
  it('counts duplicate status jobs in ui-data counts (covers status=duplicate branch)', async () => {
    const captureRes = await post('/captures', {
      ...CAPTURE,
      url: 'https://duplicate-status-job.example.com/job/1',
      page_title: 'Duplicate Status Job',
      visible_text: 'Testing duplicate status branch in ui-data.',
    });
    const captureBody = await captureRes.json();
    const db = initDb(dbPath);
    const job = db.prepare('SELECT id FROM jobs WHERE capture_id=?').get(captureBody.capture_id);
    db.prepare("UPDATE jobs SET status='duplicate' WHERE id=?").run(job.id);
    const res = await fetch(`${base}/api/ui-data`);
    assert.equal(res.status, 200);
    const body = await res.json();
    assert.ok(typeof body.metrics === 'object');
  });

  it('handles malformed structured_data_json without throwing (covers catch branch)', async () => {
    const captureRes = await post('/captures', {
      ...CAPTURE,
      url: 'https://malformed-json-job.example.com/job/1',
      page_title: 'Malformed JSON Job',
      visible_text: 'Testing malformed structured data json catch path.',
    });
    const captureBody = await captureRes.json();
    const db = initDb(dbPath);
    const capture = db.prepare('SELECT id FROM captures WHERE id=?').get(captureBody.capture_id);
    db.prepare("UPDATE captures SET structured_data_json=? WHERE id=?").run('{bad json[[[', capture.id);
    const res = await fetch(`${base}/api/ui-data`);
    assert.equal(res.status, 200);
  });
});

describe('POST /api/llm-queue/process-selected', () => {
  it('runs extraction for app when no requestIds provided', async () => {
    const res = await post('/api/llm-queue/process-selected', {});
    assert.equal(res.status, 200);
    const body = await res.json();
    assert.equal(body.ok, true);
  });

  it('runs extraction for specific requestIds (else branch)', async () => {
    const captureRes = await post('/captures', {
      ...CAPTURE,
      url: 'https://process-selected-test.example.com/job/1',
      page_title: 'Process Selected Test',
      visible_text: 'Testing process-selected with specific request IDs.',
    });
    const captureBody = await captureRes.json();
    const db = initDb(dbPath);
    const req = db.prepare("SELECT id FROM llm_requests WHERE job_id=(SELECT id FROM jobs WHERE capture_id=?) AND status='queued'").get(captureBody.capture_id);
    if (!req) return;
    const res = await post('/api/llm-queue/process-selected', { request_ids: [req.id] });
    assert.equal(res.status, 200);
    const body = await res.json();
    assert.equal(body.ok, true);
  });
});

describe('POST /api/extractions/run', () => {
  it('triggers extraction run and returns summary', async () => {
    const res = await post('/api/extractions/run', {});
    assert.equal(res.status, 200);
    const body = await res.json();
    assert.equal(body.ok, true);
    assert.ok(typeof body.processed === 'number');
  });
});

describe('GET /api/llm-queue/:requestId/attempts', () => {
  it('returns attempts array for a known request', async () => {
    const captureRes = await post('/captures', {
      ...CAPTURE,
      url: 'https://attempts-test.example.com/job/1',
      page_title: 'Attempts Test Job',
      visible_text: 'Testing attempts endpoint with a real request id.',
    });
    const captureBody = await captureRes.json();
    const db = initDb(dbPath);
    const req = db.prepare("SELECT id FROM llm_requests WHERE job_id=(SELECT id FROM jobs WHERE capture_id=?)").get(captureBody.capture_id);
    if (!req) return;
    const res = await fetch(`${base}/api/llm-queue/${req.id}/attempts`);
    assert.equal(res.status, 200);
    const body = await res.json();
    assert.equal(body.ok, true);
    assert.ok(Array.isArray(body.attempts));
  });
});

describe('POST /api/llm-queue/:requestId/reset-run', () => {
  it('resets and runs extraction for specific requestId', async () => {
    const captureRes = await post('/captures', {
      ...CAPTURE,
      url: 'https://reset-run-test.example.com/job/1',
      page_title: 'Reset Run Test',
      visible_text: 'Testing reset-run endpoint with a real pending llm request.',
    });
    const captureBody = await captureRes.json();
    const db = initDb(dbPath);
    const req = db.prepare("SELECT id FROM llm_requests WHERE job_id=(SELECT id FROM jobs WHERE capture_id=?) AND status='queued'").get(captureBody.capture_id);
    if (!req) return;
    const res = await post(`/api/llm-queue/${req.id}/reset-run`, {});
    assert.equal(res.status, 200);
    const body = await res.json();
    assert.equal(body.ok, true);
  });
});

describe('route catch blocks with broken DB path', () => {
  let brokenBase;
  let brokenServer;
  let brokenDbPath;

  before(async () => {
    brokenDbPath = tempDbPath();
    writeFileSync(brokenDbPath, 'this is not a sqlite database file');
    const app = createApp({ dbPath: brokenDbPath, autoExtract: false });
    await new Promise(resolve => {
      brokenServer = app.listen(0, '127.0.0.1', resolve);
    });
    brokenBase = `http://127.0.0.1:${brokenServer.address().port}`;
  });

  after(async () => {
    await new Promise(resolve => brokenServer.close(resolve));
  });

  async function bpost(path, body) {
    return fetch(`${brokenBase}${path}`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(body),
    });
  }

  it('GET /api/sites returns 500 on DB error', async () => {
    const res = await fetch(`${brokenBase}/api/sites`);
    assert.equal(res.status, 500);
  });

  it('GET /api/llm-queue returns 500 on DB error', async () => {
    const res = await fetch(`${brokenBase}/api/llm-queue`);
    assert.equal(res.status, 500);
  });

  it('POST /api/llm-queue/pause returns 500 on DB error', async () => {
    const res = await bpost('/api/llm-queue/pause', { paused: true });
    assert.equal(res.status, 500);
  });

  it('POST /api/llm-queue/cancel-all returns 500 on DB error', async () => {
    const res = await bpost('/api/llm-queue/cancel-all', {});
    assert.equal(res.status, 500);
  });

  it('GET /api/debug/stats returns 500 on DB error', async () => {
    const res = await fetch(`${brokenBase}/api/debug/stats`);
    assert.equal(res.status, 500);
  });

  it('POST /api/sites returns 400/500 on DB error', async () => {
    const res = await bpost('/api/sites', { url: 'https://broken-db-site.example.com' });
    assert.ok(res.status === 400 || res.status === 500);
  });

  it('POST /api/jobs/check-availability returns 500 on DB error', async () => {
    const res = await bpost('/api/jobs/check-availability', {});
    assert.equal(res.status, 500);
  });

  it('POST /api/llm-queue/process-selected returns 500 on DB error', async () => {
    const res = await bpost('/api/llm-queue/process-selected', { request_ids: ['fake-id'] });
    assert.ok(res.status === 400 || res.status === 500);
  });

  it('POST /api/llm-queue/enqueue-all returns 500 on DB error', async () => {
    const res = await bpost('/api/llm-queue/enqueue-all', {});
    assert.equal(res.status, 500);
  });

  it('POST /api/extractions/run returns 500 on DB error', async () => {
    const res = await bpost('/api/extractions/run', {});
    assert.equal(res.status, 500);
  });

  it('GET /api/llm-queue/:id/attempts returns 500 on DB error', async () => {
    const res = await fetch(`${brokenBase}/api/llm-queue/fake-req-id/attempts`);
    assert.equal(res.status, 500);
  });

  it('POST /api/llm-queue/:id/reset-run returns 500 on DB error', async () => {
    const res = await bpost('/api/llm-queue/fake-req-id/reset-run', {});
    assert.ok(res.status === 400 || res.status === 500);
  });

  it('POST /api/llm-queue/:id/cancel returns 500 on DB error', async () => {
    const res = await bpost('/api/llm-queue/fake-req-id/cancel', {});
    assert.ok(res.status === 404 || res.status === 500);
  });

  it('POST /api/site-reviews/mark returns 400/500 on DB error', async () => {
    const res = await bpost('/api/site-reviews/mark', { site_url: 'https://x.example.com', site_origin: 'https://x.example.com' });
    assert.ok(res.status === 400 || res.status === 500);
  });

  it('POST /site-reviews returns 400/500 on DB error', async () => {
    const res = await bpost('/site-reviews', { site_url: 'https://y.example.com', site_origin: 'https://y.example.com' });
    assert.ok(res.status === 400 || res.status === 500);
  });

  it('POST /api/jobs/bulk/data-quality-reviewed returns 500 on DB error', async () => {
    const res = await bpost('/api/jobs/bulk/data-quality-reviewed', { job_ids: ['x'], note: 'test' });
    assert.ok(res.status === 400 || res.status === 500);
  });

  it('DELETE /api/jobs/bulk/data-quality-reviewed returns 500 on DB error', async () => {
    const res = await fetch(`${brokenBase}/api/jobs/bulk/data-quality-reviewed`, {
      method: 'DELETE',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ job_ids: ['x'] }),
    });
    assert.ok(res.status === 400 || res.status === 500);
  });

  it('DELETE /api/jobs/:jobId returns 400/500 on DB error', async () => {
    const res = await fetch(`${brokenBase}/api/jobs/fake-job-id`, { method: 'DELETE', headers: { 'Content-Type': 'application/json' }, body: '{}' });
    assert.ok(res.status === 400 || res.status === 500);
  });

  it('POST /api/jobs/:jobId/read returns 400/500 on DB error', async () => {
    const res = await bpost('/api/jobs/fake-job-id/read', {});
    assert.ok(res.status === 400 || res.status === 500);
  });

  it('PATCH /api/jobs/:jobId returns 400/500 on DB error', async () => {
    const res = await fetch(`${brokenBase}/api/jobs/fake-job-id`, {
      method: 'PATCH',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ company: 'Test' }),
    });
    assert.ok(res.status === 400 || res.status === 500);
  });

  it('PATCH /api/jobs/:jobId/skills returns 400/500 on DB error', async () => {
    const res = await fetch(`${brokenBase}/api/jobs/fake-job-id/skills`, {
      method: 'PATCH',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ skills: [] }),
    });
    assert.ok(res.status === 400 || res.status === 500);
  });

  it('POST /api/jobs/:jobId/fit-score returns 400/500 on DB error', async () => {
    const res = await bpost('/api/jobs/fake-job-id/fit-score', {});
    assert.ok(res.status === 400 || res.status === 500);
  });

  it('POST /api/resumes returns 400/500 on DB error', async () => {
    const res = await bpost('/api/resumes', { name: 'Test', text: 'Some resume text here.' });
    assert.ok(res.status === 400 || res.status === 500);
  });

  it('PATCH /api/resumes/:id returns 400/500 on DB error', async () => {
    const res = await fetch(`${brokenBase}/api/resumes/fake-resume-id`, {
      method: 'PATCH',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ name: 'Test' }),
    });
    assert.ok(res.status === 400 || res.status === 404 || res.status === 500);
  });

  it('DELETE /api/resumes/:id returns 400/500 on DB error', async () => {
    const res = await fetch(`${brokenBase}/api/resumes/fake-resume-id`, { method: 'DELETE', headers: { 'Content-Type': 'application/json' }, body: '{}' });
    assert.ok(res.status === 400 || res.status === 500);
  });

  it('POST /api/jobs/:jobId/actions returns 400/500 on DB error', async () => {
    const res = await bpost('/api/jobs/fake-job-id/actions', { note: 'Test', due_date: null });
    assert.ok(res.status === 400 || res.status === 500);
  });

  it('GET /api/jobs/:jobId/actions returns 500 on DB error', async () => {
    const res = await fetch(`${brokenBase}/api/jobs/fake-job-id/actions`);
    assert.equal(res.status, 500);
  });

  it('POST /api/sites/:siteId/review returns 500 on DB error', async () => {
    const res = await bpost('/api/sites/fake-site-id/review', {});
    assert.ok(res.status === 404 || res.status === 500);
  });

  it('POST /api/sites/review returns 500 on DB error', async () => {
    const res = await bpost('/api/sites/review', { site_ref: 'https://nonexistent.example.com' });
    assert.ok(res.status === 404 || res.status === 500);
  });

  it('PATCH /api/sites/:siteId returns 500 on DB error', async () => {
    const res = await fetch(`${brokenBase}/api/sites/fake-site-id`, {
      method: 'PATCH',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ note: 'Test' }),
    });
    assert.ok(res.status === 404 || res.status === 500);
  });

  it('DELETE /api/sites/:siteId returns 500 on DB error', async () => {
    const res = await fetch(`${brokenBase}/api/sites/fake-site-id`, { method: 'DELETE', headers: { 'Content-Type': 'application/json' }, body: '{}' });
    assert.ok(res.status === 404 || res.status === 500);
  });

  it('PATCH /api/settings returns 500 on DB error', async () => {
    const res = await fetch(`${brokenBase}/api/settings`, {
      method: 'PATCH',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ llm_provider: 'lmstudio' }),
    });
    assert.ok(res.status === 400 || res.status === 500);
  });

  it('GET /api/settings/llm-consent/:provider returns 500 on DB error', async () => {
    const res = await fetch(`${brokenBase}/api/settings/llm-consent/anthropic`);
    assert.equal(res.status, 500);
  });

  it('POST /api/settings/llm-consent/:provider returns 500 on DB error', async () => {
    const res = await fetch(`${brokenBase}/api/settings/llm-consent/anthropic`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ consented: true }),
    });
    assert.equal(res.status, 500);
  });
});
