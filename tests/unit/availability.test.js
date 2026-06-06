import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { checkJobsAvailability, checkStaleJobsAvailability, checkUrl, maybeRunStaleAvailabilityCheck, _normalizeUrlForCompare } from '../../server/availability.js';
import { initDb, insertCapture, setSetting } from '../../server/db.js';
import { cleanupDb, tempDbPath } from '../helpers.js';

function response({ url, status = 200, body = '' }) {
  return {
    url,
    status,
    async text() {
      return body;
    },
  };
}

describe('normalizeUrlForCompare (error path)', () => {
  it('returns cleaned string for invalid URLs instead of throwing', () => {
    const result = _normalizeUrlForCompare('not a url at all///');
    assert.equal(typeof result, 'string');
    // strips trailing slashes, does not throw
    assert.doesNotMatch(result, /\/+$/);
  });

  it('returns empty string for null/undefined', () => {
    assert.equal(_normalizeUrlForCompare(null), '');
    assert.equal(_normalizeUrlForCompare(undefined), '');
  });
});

describe('checkUrl', () => {
  it('returns unavailable for HTTP 404', async () => {
    const result = await checkUrl(
      { id: 'j1', url: 'https://example.com/job/1', title: 'Engineer' },
      async () => ({ url: 'https://example.com/job/1', status: 404, async text() { return 'not found'; } })
    );
    assert.equal(result.available, false);
    assert.match(result.reason, /404/);
  });

  it('returns unavailable for HTTP 410', async () => {
    const result = await checkUrl(
      { id: 'j2', url: 'https://example.com/job/2', title: 'Engineer' },
      async () => ({ url: 'https://example.com/job/2', status: 410, async text() { return 'gone'; } })
    );
    assert.equal(result.available, false);
    assert.match(result.reason, /410/);
  });

  it('returns available with reason timeout on AbortError', async () => {
    const result = await checkUrl(
      { id: 'j3', url: 'https://example.com/job/3', title: 'Engineer' },
      async () => { const e = new Error('aborted'); e.name = 'AbortError'; throw e; }
    );
    assert.equal(result.available, true);
    assert.equal(result.reason, 'timeout');
  });

  it('returns unavailable when body contains a known gone pattern', async () => {
    const result = await checkUrl(
      { id: 'j4', url: 'https://example.com/job/4', title: 'Software Engineering Role Here' },
      async () => ({ url: 'https://example.com/job/4', status: 200, async text() { return 'sorry, this job is no longer available.'; } })
    );
    assert.equal(result.available, false);
    assert.match(result.reason, /body:/);
  });

  it('returns available with generic error reason on non-AbortError', async () => {
    const result = await checkUrl(
      { id: 'j5', url: 'https://example.com/job/5', title: 'Engineer' },
      async () => { throw new Error('ECONNREFUSED'); }
    );
    assert.equal(result.available, true);
    assert.match(result.reason, /error:/);
  });

  it('marks a job unavailable when a job URL redirects to a company page', async () => {
    const result = await checkUrl(
      {
        id: 'job_1',
        url: 'https://www.builtinseattle.com/job/technical-program-manager/123',
        title: 'Technical Program Manager',
      },
      async () => response({
        url: 'https://www.builtinseattle.com/company/deepgram',
        body: 'Deepgram Seattle Office: Careers, Perks + Culture',
      })
    );

    assert.equal(result.available, false);
    assert.match(result.reason, /redirected to non-job page/);
  });

  it('marks a redirected job unavailable when the final page is missing the title', async () => {
    const result = await checkUrl(
      {
        id: 'job_1',
        url: 'https://jobs.example.com/postings/123',
        title: 'Principal Technical Program Manager',
      },
      async () => response({
        url: 'https://jobs.example.com/postings/456',
        body: 'Senior Product Manager Apply now',
      })
    );

    assert.equal(result.available, false);
    assert.match(result.reason, /missing title/);
  });

  it('allows canonical redirects when the final page still contains the title', async () => {
    const result = await checkUrl(
      {
        id: 'job_1',
        url: 'https://jobs.example.com/postings/123?src=board',
        title: 'Principal Technical Program Manager',
      },
      async () => response({
        url: 'https://jobs.example.com/postings/123',
        body: 'Principal Technical Program Manager Apply now',
      })
    );

    assert.equal(result.available, true);
  });

  it('marks unavailable when redirected to a same-domain search page', async () => {
    const result = await checkUrl(
      { id: 'j11', url: 'https://careers.example.com/jobs/postings/456', title: 'Data Engineer' },
      async () => response({ url: 'https://careers.example.com/careers/search', body: 'Data Engineer posting here' })
    );
    assert.equal(result.available, false);
    assert.match(result.reason, /redirected/);
  });

  it('returns available for cross-domain redirect when title is present', async () => {
    const result = await checkUrl(
      { id: 'j12', url: 'https://board.example.com/job/123', title: 'Senior Software Engineer Role' },
      async () => response({ url: 'https://company.example.org/jobs/123', body: 'Senior Software Engineer Role open position apply now' })
    );
    assert.equal(result.available, true);
  });

  it('handles invalid job URL causing exception in redirectedToNonJobPage (catch path)', async () => {
    const result = await checkUrl(
      { id: 'j99', url: 'not-a-valid-url', title: 'Senior Software Engineer' },
      async () => ({ url: 'https://different.example.com/other-page', status: 200, async text() { return 'Senior Software Engineer available here'; } })
    );
    assert.equal(result.available, true);
  });

  it('marks Levels.fyi job URLs unavailable when redirected to a generic jobs page', async () => {
    const result = await checkUrl(
      {
        id: 'job_14',
        url: 'https://www.levels.fyi/jobs/title/technical-program-manager?jobId=138073367340032710',
        title: 'Sr. Staff Technical Program Manager - DoW',
      },
      async () => response({
        url: 'https://www.levels.fyi/jobs/title/technical-program-manager',
        body: 'Technical Program Manager Jobs Search filters',
      })
    );

    assert.equal(result.available, false);
    assert.match(result.reason, /missing title/);
  });
});

describe('stale availability checks', () => {
  it('checks only stale active jobs and marks unavailable ones', async () => {
    const dbPath = tempDbPath();
    try {
      initDb(dbPath);
      const stale = insertCapture({
        url: 'data:text/plain,job%20no%20longer%20available',
        page_title: 'Old Job',
        visible_text: 'Old job capture',
      }, dbPath);
      const fresh = insertCapture({
        url: 'data:text/plain,Principal%20Technical%20Program%20Manager',
        page_title: 'Fresh Job',
        visible_text: 'Fresh job capture',
      }, dbPath);
      const db = initDb(dbPath);
      db.prepare("UPDATE captures SET captured_at=? WHERE id=?").run('2026-04-01T00:00:00.000Z', stale.capture_id);
      db.prepare("UPDATE captures SET captured_at=? WHERE id=?").run(new Date().toISOString(), fresh.capture_id);

      const result = await checkStaleJobsAvailability(dbPath, { staleDays: 21, limit: 10 });
      assert.equal(result.checked, 1);
      assert.equal(result.unavailable, 1);
      assert.equal(result.marked, 1);

      const statuses = db.prepare(`SELECT c.page_title, j.status FROM jobs j JOIN captures c ON c.id=j.capture_id`).all();
      assert.equal(statuses.find(r => r.page_title === 'Old Job').status, 'not_available');
      assert.equal(statuses.find(r => r.page_title === 'Fresh Job').status, 'saved');
    } finally {
      cleanupDb(dbPath);
    }
  });

  it('skips automatic stale checks when disabled or interval has not elapsed', async () => {
    const dbPath = tempDbPath();
    try {
      const db = initDb(dbPath);
      setSetting(db, 'availability_auto_check_enabled', 'false');
      let result = await maybeRunStaleAvailabilityCheck(dbPath);
      assert.equal(result.skipped, true);
      assert.equal(result.reason, 'disabled');

      setSetting(db, 'availability_auto_check_enabled', 'true');
      setSetting(db, 'availability_last_auto_check_at', new Date().toISOString());
      result = await maybeRunStaleAvailabilityCheck(dbPath);
      assert.equal(result.skipped, true);
      assert.equal(result.reason, 'interval');
    } finally {
      cleanupDb(dbPath);
    }
  });

  it('runs check when enabled and interval has elapsed', async () => {
    const dbPath = tempDbPath();
    try {
      const db = initDb(dbPath);
      setSetting(db, 'availability_auto_check_enabled', 'true');
      // Set last check to a long time ago (beyond the interval)
      setSetting(db, 'availability_last_auto_check_at', '2020-01-01T00:00:00.000Z');
      const result = await maybeRunStaleAvailabilityCheck(dbPath);
      assert.equal(result.skipped, false);
      assert.ok(typeof result.checked === 'number');
    } finally {
      cleanupDb(dbPath);
    }
  });
});

describe('checkJobsAvailability', () => {
  it('returns checked:0 when there are no active jobs', async () => {
    const dbPath = tempDbPath();
    try {
      initDb(dbPath);
      const result = await checkJobsAvailability(dbPath);
      assert.equal(result.checked, 0);
      assert.equal(result.unavailable, 0);
      assert.equal(result.marked, 0);
    } finally {
      cleanupDb(dbPath);
    }
  });

  it('checks active jobs and marks unavailable ones', async () => {
    const dbPath = tempDbPath();
    const originalFetch = globalThis.fetch;
    try {
      initDb(dbPath);
      insertCapture({ url: 'https://check-available.example.com/job/1', page_title: 'Good Job', visible_text: 'Available job' }, dbPath);
      insertCapture({ url: 'https://check-gone.example.com/job/2', page_title: 'Gone Job', visible_text: 'Gone job' }, dbPath);

      globalThis.fetch = async (url) => {
        if (String(url).includes('check-gone')) {
          return { url, status: 404, async text() { return 'not found'; } };
        }
        return { url, status: 200, async text() { return 'Job posting available'; } };
      };

      const result = await checkJobsAvailability(dbPath);
      assert.equal(result.checked, 2);
      assert.equal(result.unavailable, 1);
      assert.equal(result.marked, 1);
    } finally {
      globalThis.fetch = originalFetch;
      cleanupDb(dbPath);
    }
  });
});
