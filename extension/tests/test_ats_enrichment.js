// Lever and Ashby state pay OUTSIDE the description body, so text parsing can never recover it.
//
// Lever returns a structured `salaryRange` and omits the figures from the description entirely
// (saviynt/c34f16eb — "$220,000 - $240,000" appears nowhere in description/lists/additional), and
// Ashby renders compensation in a sidebar the page capture misses ("$153K – $180K • Offers Equity"
// on tilthq/ffa705ba, absent from the stored visible text). Both expose it on a public API.
//
// Run: node --test extension/tests/test_ats_enrichment.js
'use strict';
const { describe, test } = require('node:test');
const assert = require('node:assert/strict');
const path = require('node:path');
const fs = require('node:fs');
const vm = require('node:vm');

const source = fs.readFileSync(path.join(__dirname, '../service_worker.js'), 'utf8');

// Evaluate just the pure helpers, so these are behavioural rather than string-matching assertions.
function extract(name, kind) {
  const marker = kind === 'const' ? `const ${name} =` : `function ${name}(`;
  const start = source.indexOf(marker);
  assert.ok(start !== -1, `${name} must exist in service_worker.js`);
  if (kind === 'const') return source.slice(start, source.indexOf('\n', start) + 1);
  // Walk braces to the end of the function.
  let i = source.indexOf('{', start);
  let depth = 0;
  for (let j = i; j < source.length; j += 1) {
    if (source[j] === '{') depth += 1;
    else if (source[j] === '}') {
      depth -= 1;
      if (depth === 0) return source.slice(start, j + 1);
    }
  }
  throw new Error(`could not extract ${name}`);
}

const sandbox = {};
vm.createContext(sandbox);
// `const` is block-scoped and never becomes a property of the vm context, so it would read back as
// undefined — and `"…".match(undefined)` quietly returns an empty match rather than null.
const extracted = [
  extract('LEVER_URL_RE', 'const'),
  extract('ASHBY_URL_RE', 'const'),
  extract('leverSalaryPosting'),
].join('\n').replace(/^const /gm, 'var ');
vm.runInContext(extracted, sandbox);
// `instanceof` is realm-bound: a RegExp built inside the vm context is not an instance of the host's
// RegExp, so identity has to be checked structurally.
const isRegExp = (v) => Object.prototype.toString.call(v) === '[object RegExp]';
assert.ok(isRegExp(sandbox.LEVER_URL_RE), 'LEVER_URL_RE must load as a RegExp');
assert.ok(isRegExp(sandbox.ASHBY_URL_RE), 'ASHBY_URL_RE must load as a RegExp');

describe('ATS enrichment: URL recognition', () => {
  test('matches the reported Lever posting', () => {
    const m = 'https://jobs.lever.co/saviynt/c34f16eb-a137-4457-822a-84608055cfdc'.match(sandbox.LEVER_URL_RE);
    assert.ok(m, 'Lever posting URL must match');
    assert.equal(m[1], 'saviynt');
    assert.equal(m[2], 'c34f16eb-a137-4457-822a-84608055cfdc');
  });

  test('matches the reported Ashby posting', () => {
    const m = 'https://jobs.ashbyhq.com/tilthq/ffa705ba-4597-478a-9f88-dc33b006b93d'.match(sandbox.ASHBY_URL_RE);
    assert.ok(m, 'Ashby posting URL must match');
    assert.equal(m[1], 'tilthq');
  });

  test('matches Lever regional hosts', () => {
    assert.ok('https://jobs.eu.lever.co/acme/c34f16eb-a137-4457-822a-84608055cfdc'.match(sandbox.LEVER_URL_RE));
  });

  test('ignores board listings and unrelated hosts', () => {
    assert.equal('https://jobs.lever.co/saviynt'.match(sandbox.LEVER_URL_RE), null);
    assert.equal('https://jobs.ashbyhq.com/tilthq'.match(sandbox.ASHBY_URL_RE), null);
    assert.equal('https://example.com/jobs/123'.match(sandbox.LEVER_URL_RE), null);
    assert.equal('https://notlever.co/acme/c34f16eb-a137-4457-822a-84608055cfdc'.match(sandbox.ASHBY_URL_RE), null);
  });
});

describe('ATS enrichment: Lever salary mapping', () => {
  test('maps the reported salaryRange to schema.org baseSalary', () => {
    const out = sandbox.leverSalaryPosting({
      salaryRange: { min: 220000, max: 240000, currency: 'USD', interval: 'per-year-salary' },
    });
    assert.equal(out.currency, 'USD');
    assert.equal(out.value.minValue, 220000);
    assert.equal(out.value.maxValue, 240000);
    assert.equal(out.value.unitText, 'YEAR', 'per-year-salary must map to YEAR');
  });

  test('maps hourly and monthly intervals', () => {
    const hourly = sandbox.leverSalaryPosting({ salaryRange: { min: 80, max: 100, interval: 'per-hour-wage' } });
    assert.equal(hourly.value.unitText, 'HOUR');
    const monthly = sandbox.leverSalaryPosting({ salaryRange: { min: 8000, interval: 'per-month-salary' } });
    assert.equal(monthly.value.unitText, 'MONTH');
  });

  test('defaults the currency rather than emitting nothing', () => {
    const out = sandbox.leverSalaryPosting({ salaryRange: { min: 100000, max: 120000 } });
    assert.equal(out.currency, 'USD');
  });

  test('returns null when no pay is stated, so nothing is invented', () => {
    assert.equal(sandbox.leverSalaryPosting({}), null);
    assert.equal(sandbox.leverSalaryPosting({ salaryRange: null }), null);
    assert.equal(sandbox.leverSalaryPosting({ salaryRange: { currency: 'USD' } }), null);
  });
});

describe('ATS enrichment: wiring', () => {
  test('runs on every capture, after Greenhouse', () => {
    assert.ok(source.includes('await enrichWithATS('), 'enrichWithATS must be called during capture');
    assert.ok(
      source.indexOf('enrichWithGreenhouse({') < source.indexOf('await enrichWithATS('),
      'Greenhouse keeps its richer path and runs first'
    );
  });

  test('is best-effort — a failed lookup returns the payload unchanged', () => {
    const fn = extract('enrichWithATS');
    assert.ok(fn.includes('return payload'), 'a capture must never fail because enrichment did');
  });

  test('bounds the request so a stalled API cannot block capture', () => {
    const fn = extract('fetchJSON');
    assert.ok(fn.includes('new AbortController()'));
    assert.ok(fn.includes('signal: controller.signal'));
    assert.ok(fn.includes('ATS_TIMEOUT_MS'));
  });

  test('declares the API hosts, without which the fetch is blocked by CORS', () => {
    const manifest = JSON.parse(fs.readFileSync(path.join(__dirname, '../manifest.json'), 'utf8'));
    assert.ok(manifest.host_permissions.includes('https://api.lever.co/*'));
    assert.ok(manifest.host_permissions.includes('https://api.ashbyhq.com/*'));
  });
});
