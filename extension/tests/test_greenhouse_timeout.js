// Verify Greenhouse enrichment uses AbortController with a timeout so a stalled
// API call cannot block capture indefinitely.
// Run: node --test extension/tests/test_greenhouse_timeout.js
'use strict';
const { describe, test } = require('node:test');
const assert = require('node:assert/strict');
const path = require('node:path');
const fs = require('node:fs');

const source = fs.readFileSync(path.join(__dirname, '../capture.js'), 'utf8');

// Extract fetchGreenhouseJobData function body for narrower assertions.
const fnStart = source.indexOf('async function fetchGreenhouseJobData(');
const fnEnd = source.indexOf('\n  async function capturePage(', fnStart);
const fnBody = source.slice(fnStart, fnEnd);

describe('capture.js: Greenhouse enrichment timeout', () => {
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
