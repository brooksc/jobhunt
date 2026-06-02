import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'fs';
import { runInThisContext } from 'vm';
import { resolve } from 'path';

function loadCsvHelpers() {
  delete globalThis.jobhuntCsv;
  const script = readFileSync(resolve('extension/export_csv.js'), 'utf8');
  runInThisContext(script, { filename: 'extension/export_csv.js' });
  return globalThis.jobhuntCsv;
}

describe('extension CSV export', () => {
  it('exports queued captures with escaped text fields', () => {
    const csv = loadCsvHelpers();
    const output = csv.queueToCsv([
      {
        queued_at: '2026-06-01T12:00:00.000Z',
        payload: {
          captured_at: '2026-06-01T11:59:00.000Z',
          page_title: 'Senior Engineer, Platform',
          url: 'https://example.com/job',
          canonical_url: 'https://example.com/jobs/123',
          selected_text: 'Selected "summary"',
          visible_text: 'Line 1\nLine 2',
          user_note: 'Follow up'
        }
      }
    ]);

    assert.equal(output, [
      'captured_at,page_title,url,canonical_url,selected_text,visible_text,user_note,queued_at',
      '2026-06-01T11:59:00.000Z,"Senior Engineer, Platform",https://example.com/job,https://example.com/jobs/123,"Selected ""summary""","Line 1\nLine 2",Follow up,2026-06-01T12:00:00.000Z'
    ].join('\r\n'));
  });

  it('builds stable export filenames from timestamps', () => {
    const csv = loadCsvHelpers();
    assert.equal(
      csv.csvFilename(new Date('2026-06-01T12:34:56Z')),
      'jobhunt-captures-20260601123456.csv'
    );
  });
});
