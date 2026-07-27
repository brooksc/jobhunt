// Verify Greenhouse enrichment uses AbortController with a timeout so a stalled
// API call cannot block capture indefinitely.
//
// The enrichment lives in the SERVICE WORKER, not the injected capture script: capture.js is injected
// with world:"MAIN" (page context), so its fetch to boards-api.greenhouse.io was an ordinary
// cross-origin request. That API sends no Access-Control-Allow-Origin, so CORS blocked it on every
// capture and it silently returned null — 58 of 84 stored Greenhouse captures had no structured data.
// Run: node --test extension/tests/test_greenhouse_timeout.js
'use strict';
const { describe, test } = require('node:test');
const assert = require('node:assert/strict');
const path = require('node:path');
const fs = require('node:fs');

const source = fs.readFileSync(path.join(__dirname, '../service_worker.js'), 'utf8');

// Extract fetchGreenhouseJobData function body for narrower assertions.
const fnStart = source.indexOf('async function fetchGreenhouseJobData(');
const fnEnd = source.indexOf('\nasync function enrichWithGreenhouse(', fnStart);
const fnBody = source.slice(fnStart, fnEnd);

describe('service_worker.js: Greenhouse enrichment timeout', () => {
  test('defines a GREENHOUSE_TIMEOUT_MS constant', () => {
    assert.ok(source.includes('GREENHOUSE_TIMEOUT_MS'), 'GREENHOUSE_TIMEOUT_MS constant must be defined');
  });

  test('creates an AbortController before fetching', () => {
    assert.ok(fnBody.includes('new AbortController()'), 'must create an AbortController');
  });

  test('passes signal to fetch', () => {
    assert.ok(fnBody.includes('signal: controller.signal'), 'fetch must receive controller.signal');
  });

  test('sets a timer with GREENHOUSE_TIMEOUT_MS', () => {
    assert.ok(
      fnBody.includes('GREENHOUSE_TIMEOUT_MS') && fnBody.includes('controller.abort()'),
      'must schedule controller.abort() after GREENHOUSE_TIMEOUT_MS'
    );
  });

  test('clears the timer after a successful response', () => {
    // clearTimeout must be called in the success path, not only in the catch.
    const afterFetch = fnBody.slice(fnBody.indexOf('clearTimeout(timer)'));
    assert.ok(afterFetch.length > 0, 'clearTimeout must be called in the success path');
  });

  test('clears the timer in the catch block (timeout or error)', () => {
    const catchBlock = fnBody.slice(fnBody.lastIndexOf('} catch'));
    assert.ok(catchBlock.includes('clearTimeout(timer)'), 'clearTimeout must be called in the catch block');
  });

  test('returns null on timeout or API error without throwing', () => {
    const catchBlock = fnBody.slice(fnBody.lastIndexOf('} catch'));
    assert.ok(catchBlock.includes('return null'), 'catch block must return null (fail-open)');
  });
});

// --- Regression: the enrichment must run where cross-origin fetches are permitted ----------------
describe('Greenhouse enrichment runs in the service worker, not the MAIN-world page script', () => {
  const capture = fs.readFileSync(path.join(__dirname, '../capture.js'), 'utf8');
  const manifest = JSON.parse(fs.readFileSync(path.join(__dirname, '../manifest.json'), 'utf8'));

  test('capture.js does not fetch the Greenhouse API', () => {
    // Match an actual call, not the hostname — the file documents WHY the fetch moved, and that
    // explanation is worth keeping.
    const codeOnly = capture.replace(/^\s*\/\/.*$/gm, '');
    assert.ok(
      !/fetch\s*\([^)]*boards-api\.greenhouse\.io/.test(codeOnly),
      'capture.js runs in world:"MAIN"; a fetch there is cross-origin and CORS-blocked'
    );
  });

  test('the API host is declared in host_permissions', () => {
    assert.ok(
      manifest.host_permissions.includes('https://boards-api.greenhouse.io/*'),
      'the service worker cannot reach the API without an explicit host permission'
    );
  });

  test('the service worker enriches the capture payload', () => {
    assert.ok(source.includes('enrichWithGreenhouse('), 'must define the enrichment step');
    assert.ok(
      source.includes('await enrichWithGreenhouse('),
      'the captured payload must actually be passed through it'
    );
  });

  test('regional Greenhouse boards are matched', () => {
    const re = /(?:job-boards|boards)(?:\.[a-z]{2})?\.greenhouse\.io\/([^/?#]+)\/jobs\/(\d+)/;
    assert.ok(re.test('https://job-boards.eu.greenhouse.io/parloa/jobs/4719998101'), 'EU board');
    assert.ok(re.test('https://job-boards.greenhouse.io/airtable/jobs/8604559002'), 'US board');
    assert.ok(re.test('https://boards.greenhouse.io/acme/jobs/123'), 'legacy board');
  });

  test('structured_data_json stays in sync when enriched', () => {
    assert.ok(
      source.includes('structured_data_json: JSON.stringify(structured)'),
      'the server prefers the typed field; it must not go stale'
    );
  });
});
