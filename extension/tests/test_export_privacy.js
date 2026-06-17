// Tests for the CSV-export privacy notice (TASK-440).
// Run: node --test extension/tests/test_export_privacy.js
'use strict';
const { describe, test } = require('node:test');
const assert = require('node:assert/strict');
const path = require('node:path');
const fs = require('node:fs');

const statusHtml = fs.readFileSync(path.join(__dirname, '../status.html'), 'utf8');
const privacyMd = fs.readFileSync(path.join(__dirname, '../../chromestore/PRIVACY.md'), 'utf8');

describe('export privacy notice (TASK-440)', () => {
  test('status page warns the CSV contains full captured page text + notes', () => {
    const notice = statusHtml.toLowerCase();
    assert.ok(notice.includes('export-privacy'), 'privacy notice element must exist');
    // Must mention what the export contains so users know before downloading.
    assert.ok(notice.includes('captured page text'), 'must mention captured page text');
    assert.ok(notice.includes('notes') || notice.includes('note'), 'must mention notes');
    assert.ok(notice.includes('url'), 'must mention the URL');
  });

  test('store privacy policy stays consistent about CSV contents', () => {
    const md = privacyMd.toLowerCase();
    assert.ok(md.includes('csv'), 'PRIVACY.md must cover CSV export');
    assert.ok(md.includes('captured page text'), 'PRIVACY.md must say the CSV includes captured page text');
  });
});
