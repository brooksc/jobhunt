// Behaviour tests for ATS enrichment and its timeouts (TASK-687).
//
// These replace assertions that read service_worker.js and matched strings — `source.includes('await
// enrichWithATS(')`, `fnBody.includes('new AbortController()')`. Those pass whether or not the code
// is reachable, fail when a safe rename touches the text, and say nothing about what the extension
// does. Here the worker is loaded and driven with a stubbed fetch, so what is asserted is behaviour.
//
// Run: node --test extension/tests/test_ats_enrichment_behavior.js
//
// Deliberately NOT 'use strict': strict mode gives `eval` its own scope, so the worker's top-level
// functions would never reach these tests. The existing service_worker harness omits it for the same
// reason.
const { describe, test, beforeEach, afterEach } = require('node:test');
const assert = require('node:assert/strict');
const path = require('node:path');
const fs = require('node:fs');

function makeChromeStorage() {
  let data = {};
  return {
    async get(keys) {
      if (typeof keys === 'string') return { [keys]: data[keys] };
      if (Array.isArray(keys)) {
        const out = {};
        keys.forEach((k) => { if (k in data) out[k] = data[k]; });
        return out;
      }
      const out = {};
      for (const [k, def] of Object.entries(keys || {})) out[k] = k in data ? data[k] : def;
      return out;
    },
    async set(obj) { Object.assign(data, obj); },
    async remove(key) {
      (Array.isArray(key) ? key : [key]).forEach((k) => delete data[k]);
    },
    reset() { data = {}; },
  };
}

global.importScripts = () => {};
global.chrome = {
  action: { setTitle: async () => {}, setBadgeText: async () => {}, setBadgeBackgroundColor: async () => {}, onClicked: { addListener: () => {} } },
  contextMenus: { create: () => {}, update: async () => {}, onClicked: { addListener: () => {} } },
  runtime: { onInstalled: { addListener: () => {} }, onStartup: { addListener: () => {} }, onMessage: { addListener: () => {} }, getURL: (p) => `chrome-extension://test/${p}` },
  storage: { session: makeChromeStorage(), local: makeChromeStorage() },
  scripting: { executeScript: async () => [{ result: {} }] },
  tabs: { create: async () => ({ id: 1 }), remove: async () => {}, query: async () => [] },
  commands: { getAll: async () => [], onCommand: { addListener: () => {} } },
  downloads: { download: async () => 1 },
};

eval(fs.readFileSync(path.join(__dirname, '../retry_queue.js'), 'utf8'));
eval(fs.readFileSync(path.join(__dirname, '../export_csv.js'), 'utf8'));
eval(fs.readFileSync(path.join(__dirname, '../service_worker.js'), 'utf8'));

let requested = [];

beforeEach(() => { requested = []; });
afterEach(() => { global.fetch = undefined; });

/** A fetch that records every URL and answers from `routes` (a function of the URL). */
function stubFetch(routes) {
  global.fetch = async (url, options) => {
    requested.push(String(url));
    return routes(String(url), options);
  };
}

function jsonResponse(body) {
  return { ok: true, status: 200, json: async () => body, text: async () => JSON.stringify(body) };
}

describe('ATS enrichment: behaviour', () => {
  // Lever states pay outside the description, so this is the whole point of enrichment.
  test('a Lever capture gains the salary the description omits', async () => {
    stubFetch((url) => {
      if (url.includes('api.lever.co')) {
        return jsonResponse({
          salaryRange: { min: 220000, max: 240000, currency: 'USD', interval: 'per-year-salary' },
        });
      }
      throw new Error(`unexpected request: ${url}`);
    });

    const payload = { url: 'https://jobs.lever.co/saviynt/c34f16eb-1111-2222-3333-444455556666' };
    const out = await enrichWithATS(payload);

    assert.ok(requested.some((u) => u.includes('api.lever.co')), 'the Lever API must be consulted');
    const posting = (out.structured_data || []).find((e) => e && e.baseSalary);
    assert.ok(posting, 'enrichment must add a JobPosting carrying baseSalary');
    assert.equal(posting.baseSalary.value.minValue, 220000);
    assert.equal(posting.baseSalary.value.maxValue, 240000);
  });

  // Ashby renders pay in a sidebar the page capture misses, so this is the only way to get it.
  test('an Ashby capture gains the compensation the sidebar holds', async () => {
    const id = 'ffa705ba-1111-2222-3333-444455556666';
    stubFetch((url) => {
      if (url.includes('api.ashbyhq.com')) {
        return jsonResponse({
          jobs: [{
            id,
            title: 'Staff Engineer',
            descriptionPlain: 'Build things.',
            location: 'Remote - US',
            compensation: { scrapeableCompensationSalarySummary: '$153K – $180K • Offers Equity' },
          }],
        });
      }
      throw new Error(`unexpected request: ${url}`);
    });

    const out = await enrichWithATS({ url: `https://jobs.ashbyhq.com/tilthq/${id}` });
    const posting = (out.structured_data || []).find((e) => e && e['@type'] === 'JobPosting');
    assert.ok(posting, 'enrichment must add a JobPosting');
    assert.match(posting.description, /\$153K – \$180K/, 'the sidebar compensation must reach the capture');
    assert.equal(posting.jobLocation.address.addressLocality, 'Remote - US');
  });

  // Enrichment adds to the page's structured data; it must not replace it.
  test('structured data the page already published is kept', async () => {
    const id = 'c34f16eb-1111-2222-3333-444455556666';
    stubFetch(() => jsonResponse({ salaryRange: { min: 1, max: 2, currency: 'USD' } }));

    const existing = { '@type': 'Organization', name: 'Acme' };
    const out = await enrichWithATS({
      url: `https://jobs.lever.co/acme/${id}`,
      structured_data: [existing],
    });

    assert.ok(
      (out.structured_data || []).some((e) => e && e['@type'] === 'Organization'),
      'the page\'s own structured data must survive enrichment'
    );
    assert.ok(out.structured_data.length >= 2, 'and the enrichment is added alongside it');
  });

  // The JSON mirror is what the app actually reads, so it has to agree with the array.
  test('the serialized mirror matches the structured data array', async () => {
    const id = 'c34f16eb-1111-2222-3333-444455556666';
    stubFetch(() => jsonResponse({
      salaryRange: { min: 220000, max: 240000, currency: 'USD', interval: 'per-year-salary' },
    }));

    const out = await enrichWithATS({ url: `https://jobs.lever.co/acme/${id}` });
    assert.deepEqual(
      JSON.parse(out.structured_data_json), out.structured_data,
      'structured_data_json must serialize the same array the payload carries'
    );
  });

  // The capture is the thing that matters; enrichment is a bonus.
  test('a failed lookup returns the capture unchanged rather than failing it', async () => {
    stubFetch(() => { throw new Error('network down'); });

    const payload = { url: 'https://jobs.lever.co/acme/c34f16eb-1111-2222-3333-444455556666', visible_text: 'original' };
    const out = await enrichWithATS(payload);

    assert.equal(out.visible_text, 'original', 'the capture must survive a failed lookup');
  });

  test('a non-ATS URL is left alone and costs no request', async () => {
    stubFetch(() => { throw new Error('should not be called'); });

    const payload = { url: 'https://example.com/careers/123' };
    const out = await enrichWithATS(payload);

    assert.deepEqual(requested, [], 'no ATS request for a URL no provider claims');
    assert.equal(out.url, payload.url);
  });

  // A stalled API must not hold a capture open forever.
  test('a stalled ATS request is abandoned instead of hanging the capture', async () => {
    global.fetch = (url, options) => new Promise((_resolve, reject) => {
      requested.push(String(url));
      // Never settle on our own: only the abort signal ends this, which is the thing being tested.
      options.signal.addEventListener('abort', () => {
        const err = new Error('aborted');
        err.name = 'AbortError';
        reject(err);
      });
    });

    const payload = { url: 'https://jobs.lever.co/acme/c34f16eb-1111-2222-3333-444455556666', visible_text: 'original' };
    const out = await enrichWithATS(payload);

    assert.ok(requested.length > 0, 'the request was made');
    assert.equal(out.visible_text, 'original', 'the capture completes despite the stall');
  });
});

describe('Greenhouse enrichment: behaviour', () => {
  test('a stalled Greenhouse request is abandoned instead of hanging the capture', async () => {
    global.fetch = (url, options) => new Promise((_resolve, reject) => {
      requested.push(String(url));
      options.signal.addEventListener('abort', () => {
        const err = new Error('aborted');
        err.name = 'AbortError';
        reject(err);
      });
    });

    // It takes the posting URL and derives board + id itself.
    const data = await fetchGreenhouseJobData('https://boards.greenhouse.io/acme/jobs/12345');
    assert.equal(data, null, 'a stalled lookup yields nothing rather than never returning');
    assert.ok(requested.some((u) => u.includes('greenhouse')), 'the Greenhouse API was consulted');
  });
});
