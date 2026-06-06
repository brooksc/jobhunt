import { describe, it, before, after } from 'node:test';
import assert from 'node:assert/strict';
import { initDb, insertCapture } from '../../server/db.js';
import { runExtractionForSelected, providerConcurrency, _resetConcurrencyState, _onSuccess, _onRateLimit } from '../../server/extract.js';
import { tempDbPath, cleanupDb, CAPTURE } from '../helpers.js';

const EXTRACTED = {
  company: 'Acme', title: 'TPM', location: 'Remote', remote_type: 'remote',
  salary_min: null, salary_max: null, salary_currency: null, salary_note: null,
  employment_type: 'full_time', seniority: 'senior', skills: ['pm'],
  summary: 's', requirements: ['r'], nice_to_haves: [], benefits: [],
  application_url: null, confidence: { location: 0.9 },
};

// Extractor mock that records how many extract() calls are in flight at once.
function trackingExtractor(provider) {
  const state = { inFlight: 0, maxInFlight: 0 };
  return {
    provider, baseUrl: 'http://x', model: 'm', state,
    async extract() {
      state.inFlight++;
      state.maxInFlight = Math.max(state.maxInFlight, state.inFlight);
      await new Promise(r => setTimeout(r, 20));
      state.inFlight--;
      return { extracted: EXTRACTED, modelName: 'm', responseFormatType: 'json_schema' };
    },
  };
}

describe('provider-aware queue concurrency', () => {
  let dbPath;
  before(() => { dbPath = tempDbPath(); initDb(dbPath); });
  after(() => cleanupDb(dbPath));

  function seedExtractRequests(n, urlPrefix) {
    const db = initDb(dbPath);
    const ids = [];
    for (let i = 0; i < n; i++) {
      insertCapture({ ...CAPTURE, url: `${urlPrefix}/${i}`, page_title: `Job ${i}`, visible_text: `Description number ${i} ${'x'.repeat(60)}` }, dbPath);
    }
    for (const row of db.prepare("SELECT lr.id FROM llm_requests lr JOIN captures c ON c.id=(SELECT capture_id FROM jobs WHERE id=lr.job_id) WHERE lr.request_type='extract' AND lr.status='queued' AND c.url LIKE ?").all(`${urlPrefix}/%`)) {
      ids.push(row.id);
    }
    return ids;
  }

  it('maps providers to a concurrency level', () => {
    assert.equal(providerConcurrency('lmstudio'), 1);
    assert.equal(providerConcurrency('custom'), 1);
    assert.equal(providerConcurrency('openai'), 5);
    assert.equal(providerConcurrency('anthropic'), 5);
    assert.equal(providerConcurrency('google'), 1); // free tier: 15 RPM, concurrent requests exhaust quota instantly
    assert.equal(providerConcurrency('openrouter'), 5);
  });

  it('runs local (lmstudio) requests strictly one at a time', async () => {
    const ids = seedExtractRequests(4, 'https://local.test');
    const extractor = trackingExtractor('lmstudio');
    const summary = await runExtractionForSelected({ dbPath, extractor, requestIds: ids, scorer: null });
    assert.equal(summary.processed, 4);
    assert.equal(summary.succeeded, 4);
    assert.equal(extractor.state.maxInFlight, 1);
  });

  it('runs hosted (openai) requests up to 5 in parallel', async () => {
    const ids = seedExtractRequests(8, 'https://hosted.test');
    const extractor = trackingExtractor('openai');
    const summary = await runExtractionForSelected({ dbPath, extractor, requestIds: ids, scorer: null });
    assert.equal(summary.processed, 8);
    assert.equal(summary.succeeded, 8);
    assert.equal(extractor.state.maxInFlight, 5); // capped at HOSTED_CONCURRENCY
  });
});

describe('dynamic concurrency (rate-limit feedback)', () => {
  it('google starts at 1', () => {
    _resetConcurrencyState();
    assert.equal(providerConcurrency('google'), 1);
  });

  it('promotes google after 10 consecutive successes', () => {
    _resetConcurrencyState();
    for (let i = 0; i < 9; i++) _onSuccess('google');
    assert.equal(providerConcurrency('google'), 1); // not yet
    _onSuccess('google'); // 10th
    assert.equal(providerConcurrency('google'), 2); // promoted
  });

  it('rate limit drops concurrency to 1 and resets streak', () => {
    _resetConcurrencyState();
    for (let i = 0; i < 10; i++) _onSuccess('google');
    assert.equal(providerConcurrency('google'), 2);
    _onRateLimit('google');
    assert.equal(providerConcurrency('google'), 1);
    // streak reset — needs another 10 to promote again
    for (let i = 0; i < 9; i++) _onSuccess('google');
    assert.equal(providerConcurrency('google'), 1);
    _onSuccess('google');
    assert.equal(providerConcurrency('google'), 2);
  });

  it('concurrency is capped at HOSTED_CONCURRENCY (5)', () => {
    _resetConcurrencyState();
    // 5 promotions × 10 successes each = 50 successes → should cap at 5
    for (let i = 0; i < 50; i++) _onSuccess('google');
    assert.equal(providerConcurrency('google'), 5);
    // One more batch of 10 should not exceed 5
    for (let i = 0; i < 10; i++) _onSuccess('google');
    assert.equal(providerConcurrency('google'), 5);
  });
});
