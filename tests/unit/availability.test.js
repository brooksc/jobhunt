import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { checkStaleJobsAvailability, checkUrl, maybeRunStaleAvailabilityCheck } from '../../server/availability.js';
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

describe('checkUrl', () => {
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
});
