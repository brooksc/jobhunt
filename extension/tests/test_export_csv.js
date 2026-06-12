// Tests for extension/export_csv.js
// Run: node --test extension/tests/test_export_csv.js
'use strict';
const { describe, test } = require('node:test');
const assert = require('node:assert/strict');
const path = require('node:path');
const fs = require('node:fs');

eval(fs.readFileSync(path.join(__dirname, '../export_csv.js'), 'utf8'));
const csv = globalThis.jobhuntCsv;

function queueItem(payloadOverrides = {}) {
  return {
    payload: {
      captured_at: '2026-01-01T00:00:00.000Z',
      page_title: 'Engineer Role',
      url: 'https://example.com/job',
      canonical_url: 'https://example.com/job',
      visible_text: 'Full job description here',
      selected_text: '',
      user_note: '',
      ...payloadOverrides
    },
    queued_at: '2026-01-01T00:00:01.000Z',
  };
}

describe('export_csv: csvEscape', () => {
  test('plain string passes through unchanged', () => {
    assert.equal(csv.csvEscape('hello world'), 'hello world');
  });

  test('string with comma is double-quoted', () => {
    assert.equal(csv.csvEscape('a,b'), '"a,b"');
  });

  test('string with LF is double-quoted', () => {
    assert.equal(csv.csvEscape('line1\nline2'), '"line1\nline2"');
  });

  test('string with CR is double-quoted', () => {
    assert.equal(csv.csvEscape('line1\rline2'), '"line1\rline2"');
  });

  test('string with double-quote is quoted and doubled', () => {
    assert.equal(csv.csvEscape('say "hello"'), '"say ""hello"""');
  });

  test('null becomes empty string', () => {
    assert.equal(csv.csvEscape(null), '');
  });

  test('undefined becomes empty string', () => {
    assert.equal(csv.csvEscape(undefined), '');
  });

  test('number is stringified', () => {
    assert.equal(csv.csvEscape(42), '42');
  });
});

describe('export_csv: queueToCsv', () => {
  test('empty queue returns header row only', () => {
    const result = csv.queueToCsv([]);
    const rows = result.split('\r\n');
    assert.equal(rows.length, 1, 'only the header row');
  });

  test('header columns are in expected order', () => {
    const result = csv.queueToCsv([]);
    const headers = result.split('\r\n')[0].split(',');
    assert.deepEqual(headers, [
      'captured_at', 'page_title', 'url', 'canonical_url',
      'selected_text', 'visible_text', 'user_note', 'queued_at'
    ]);
  });

  test('visible_text is exported (full capture scope)', () => {
    const result = csv.queueToCsv([queueItem({ visible_text: 'Job description body' })]);
    assert.ok(result.includes('Job description body'), 'visible_text must be present in CSV export');
  });

  test('selected_text is exported (explicit privacy scope)', () => {
    const result = csv.queueToCsv([queueItem({ selected_text: 'Highlighted salary line' })]);
    assert.ok(result.includes('Highlighted salary line'), 'selected_text must be present in CSV export');
  });

  test('special characters in field values are escaped', () => {
    const result = csv.queueToCsv([queueItem({ visible_text: 'Salary: $100,000\n"Base"' })]);
    assert.ok(result.includes('"Salary: $100,000\n""Base"""'));
  });

  test('uses CRLF line endings between rows', () => {
    const result = csv.queueToCsv([queueItem(), queueItem({ url: 'https://example.com/job2', canonical_url: 'https://example.com/job2' })]);
    assert.ok(result.includes('\r\n'), 'must use CRLF');
  });

  test('multiple items produce header + one row each', () => {
    const items = [queueItem(), queueItem({ url: 'https://x.com', canonical_url: 'https://x.com' })];
    const rows = csv.queueToCsv(items).split('\r\n');
    assert.equal(rows.length, 3, 'header + 2 data rows');
  });

  test('missing payload fields default to empty string', () => {
    const sparse = { payload: { url: 'https://x.com' }, queued_at: '2026-01-01T00:00:00.000Z' };
    const rows = csv.queueToCsv([sparse]).split('\r\n');
    assert.equal(rows.length, 2);
    // page_title column (index 1) should be empty
    const cols = rows[1].split(',');
    assert.equal(cols[1], '', 'missing page_title should be empty');
  });
});

describe('export_csv: csvFilename', () => {
  test('has expected prefix and .csv suffix', () => {
    const name = csv.csvFilename(new Date('2026-06-01T12:30:00Z'));
    assert.ok(name.startsWith('jobhunt-captures-'));
    assert.ok(name.endsWith('.csv'));
  });

  test('encodes timestamp without separators', () => {
    const name = csv.csvFilename(new Date('2026-06-01T12:30:00Z'));
    assert.ok(name.includes('20260601'), 'date digits present');
    assert.ok(!name.includes('-', 'jobhunt-captures-'.length), 'no hyphens in timestamp portion');
  });
});
