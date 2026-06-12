// Verify that the preflight overlay does not interpolate page-derived values into innerHTML.
// Run: node --test extension/tests/test_preflight_security.js
'use strict';
const { describe, test } = require('node:test');
const assert = require('node:assert/strict');
const path = require('node:path');
const fs = require('node:fs');

const source = fs.readFileSync(path.join(__dirname, '../capture.js'), 'utf8');

// Extract the showCapturePreflight function body for narrower assertions.
const fnStart = source.indexOf('function showCapturePreflight(');
const fnEnd = source.indexOf('\n  async function ', fnStart);
const fnBody = source.slice(fnStart, fnEnd);

describe('capture.js: preflight overlay XSS safety', () => {
  test('page-derived titleVal is not interpolated into innerHTML', () => {
    // Any template literal that embeds ${preflight.titleVal} inside an innerHTML assignment is the bug.
    const pattern = /innerHTML\s*=[\s\S]{0,2000}?\$\{preflight\.titleVal\}/;
    assert.ok(!pattern.test(fnBody), 'preflight.titleVal must not appear inside an innerHTML assignment');
  });

  test('page-derived locationVal is not interpolated into innerHTML', () => {
    const pattern = /innerHTML\s*=[\s\S]{0,2000}?\$\{preflight\.locationVal\}/;
    assert.ok(!pattern.test(fnBody), 'preflight.locationVal must not appear inside an innerHTML assignment');
  });

  test('page-derived salaryVal is not interpolated into innerHTML', () => {
    const pattern = /innerHTML\s*=[\s\S]{0,2000}?\$\{preflight\.salaryVal\}/;
    assert.ok(!pattern.test(fnBody), 'preflight.salaryVal must not appear inside an innerHTML assignment');
  });

  test('page-derived remoteVal is not interpolated into innerHTML', () => {
    const pattern = /innerHTML\s*=[\s\S]{0,2000}?\$\{preflight\.remoteVal\}/;
    assert.ok(!pattern.test(fnBody), 'preflight.remoteVal must not appear inside an innerHTML assignment');
  });

  test('textContent is used to assign page-derived check-row values', () => {
    assert.ok(
      fnBody.includes('.textContent'),
      'showCapturePreflight should use .textContent to insert page-derived values'
    );
  });

  test('cancel and open-in-app buttons are present in the static skeleton', () => {
    assert.ok(fnBody.includes('data-jh-cancel'), 'cancel button marker must be in skeleton');
    assert.ok(fnBody.includes('data-jh-open'), 'open-in-app button marker must be in skeleton');
  });

  test('countdown element is present in the static skeleton', () => {
    assert.ok(fnBody.includes('data-jh-countdown'), 'countdown element marker must be in skeleton');
  });
});
