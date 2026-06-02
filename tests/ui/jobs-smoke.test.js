import { describe, it, before, after } from 'node:test';
import assert from 'node:assert/strict';
import { chromium } from '@playwright/test';

import { createApp } from '../../server/api.js';
import { connect, initDb } from '../../server/db.js';
import { tempDbPath, cleanupDb, CAPTURE, CAPTURE2 } from '../helpers.js';

let base;
let server;
let dbPath;
let browser;

before(async () => {
  dbPath = tempDbPath();
  initDb(dbPath);
  const app = createApp({ dbPath, autoExtract: false });
  await new Promise(resolve => {
    server = app.listen(0, '127.0.0.1', resolve);
  });
  base = `http://127.0.0.1:${server.address().port}`;

  await post('/captures', CAPTURE);
  await post('/captures', CAPTURE2);
  await post('/captures', {
    url: 'https://nocurrency.example/jobs/789',
    page_title: 'Program Manager at No Currency Co',
    visible_text: 'Program manager role with salary range listed but no currency metadata.',
  });
  await post('/captures', {
    url: 'https://dupes.example/jobs/a',
    page_title: 'Duplicate TPM at Acme',
    visible_text: 'Duplicate role text for accessibility smoke.',
  });
  await post('/captures', {
    url: 'https://dupes.example/jobs/b',
    page_title: 'Duplicate TPM at Acme',
    visible_text: 'Duplicate   role text for accessibility smoke.',
  });
  seedJobRows();
  browser = await launchBrowser();
});

after(async () => {
  if (browser) await browser.close();
  if (server) await new Promise(resolve => server.close(resolve));
  if (dbPath) cleanupDb(dbPath);
});

async function post(path, body) {
  const res = await fetch(`${base}${path}`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(body),
  });
  assert.equal(res.status, 200);
  return res.json();
}

async function launchBrowser() {
  try {
    return await chromium.launch({ channel: 'chrome' });
  } catch {
    return chromium.launch();
  }
}

function seedJobRows() {
  const db = connect(dbPath);
  const rows = db.prepare('SELECT jobs.id, captures.url FROM jobs JOIN captures ON captures.id=jobs.capture_id ORDER BY jobs.job_number').all();
  assert.equal(rows.length, 5);
  db.prepare(`
    UPDATE jobs
    SET company=?, title=?, location=?, remote_type=?, salary_min=?, salary_max=?, salary_currency=?, extracted_json=?, extraction_status='succeeded', extracted_at='2026-05-31T12:00:00Z'
    WHERE id=?
  `).run('Acme', 'Principal TPM', 'Seattle, WA', 'hybrid', 120000, 220000, 'USD', JSON.stringify({
    company: 'Acme',
    title: 'Principal TPM',
    location: 'Seattle, WA',
    remote_type: 'hybrid',
    salary_min: 120000,
    salary_max: 220000,
    salary_currency: 'USD',
    salary_note: '$120k-$220k',
    meets_criteria: true,
    confidence: { location: 0.91, remote_type: 0.84, salary: 0.88, meets_criteria: 0.95 },
  }), rows[0].id);
  db.prepare(`
    UPDATE captures
    SET canonical_url=?, selected_text=?, structured_data_json=?
    WHERE url=?
  `).run(
    'https://example.com/jobs/123?canonical=1',
    'Selected job description text',
    JSON.stringify([{ '@type': 'JobPosting', title: 'Principal TPM' }]),
    CAPTURE.url
  );
  db.prepare(`
    UPDATE jobs
    SET company=?, title=?, location=?, remote_type=?, salary_min=?, salary_max=?, salary_currency=?, extraction_status='succeeded', extracted_at='2026-05-31T12:05:00Z'
    WHERE id=?
  `).run('Globex', 'Staff Program Manager', 'Remote', 'remote', 150000, 250000, 'USD', rows[1].id);
  db.prepare(`
    UPDATE jobs
    SET company=?, title=?, location=?, remote_type=?, salary_min=?, salary_max=?, salary_currency=NULL, salary_note=?, extraction_status='succeeded', extracted_at='2026-05-31T12:10:00Z'
    WHERE id=?
  `).run('No Currency Co', 'No Currency TPM', 'Remote', 'remote', 120000, 180000, 'Salary listed without currency', rows[2].id);
  db.prepare(`
    INSERT INTO llm_requests (id, job_id, request_type, status, attempt, created_at, started_at, model)
    VALUES (?, ?, 'extract', 'running', 1, ?, ?, ?)
  `).run('llm_ui_running', rows[0].id, '2026-05-31T12:20:00Z', '2026-05-31T12:20:05Z', 'gemma-ui-test');
  db.prepare(`
    INSERT INTO llm_requests (id, job_id, request_type, status, attempt, created_at, finished_at, error, model)
    VALUES (?, ?, 'extract', 'failed', 3, ?, ?, ?, ?)
  `).run('llm_ui_failed', rows[1].id, '2026-05-31T12:21:00Z', '2026-05-31T12:22:00Z', 'Retry limit reached (3 attempts).', 'gemma-ui-test');
  db.prepare(`
    INSERT INTO llm_request_attempts
      (id, request_id, job_id, request_type, attempt, status, model_requested, model_returned, response_format, started_at, finished_at, duration_ms, error, response_preview)
    VALUES (?, ?, ?, 'extract', 3, 'retry_exhausted', ?, ?, 'json_schema', ?, ?, 1250, ?, ?)
  `).run(
    'llma_ui_failed',
    'llm_ui_failed',
    rows[1].id,
    'gemma-ui-test',
    'gemma-ui-test',
    '2026-05-31T12:21:05Z',
    '2026-05-31T12:21:06Z',
    'Retry limit reached (3 attempts).',
    'plain text'
  );
}

describe('Jobs UI smoke', () => {
  it('shows data quality counts on the dashboard', async () => {
    const page = await browser.newPage();
    const pageErrors = [];
    page.on('pageerror', error => pageErrors.push(error.message));

    await page.goto(`${base}/#/dashboard`);
    await assertVisibleText(page, 'Data gaps');
    await assertVisibleText(page, 'Needs recapture');
    await assertVisibleText(page, 'AI only');
    await page.getByRole('button', { name: /Needs recapture/ }).click();
    assert.match(page.url(), /#\/quality\?issue=recapture/);
    await assertVisibleText(page, 'Browser recapture checklist');

    assert.deepEqual(pageErrors, []);
    await page.close();
  });

  it('shows actionable data quality gaps', async () => {
    const page = await browser.newPage();
    const pageErrors = [];
    page.on('pageerror', error => pageErrors.push(error.message));

    await page.goto(`${base}/#/quality`);
    await assertVisibleText(page, 'Data Quality');
    await assertVisibleText(page, 'With gaps');
    await assertVisibleText(page, 'Missing location');
    await assertVisibleText(page, 'Missing salary');
    await assertVisibleText(page, 'Short capture');
    await assertVisibleText(page, 'Likely cause');
    await assertVisibleText(page, 'Open visible');
    await assertVisibleText(page, 'Re-run AI');
    await assertVisibleText(page, 'Select in Jobs');
    await assertVisibleText(page, 'Dismiss visible');
    await assertVisibleText(page, 'Browser recapture checklist');
    await assertVisibleText(page, 'AI re-run checklist');
    await assertVisibleText(page, 'Site parsing health');
    await assertVisibleText(page, 'Capture guidance');
    await assertVisibleText(page, 'Reviewed');

    const rows = page.locator('.jh-table tbody tr');
    assert.ok(await rows.count() >= 1);
    await page.getByRole('button', { name: /Location/ }).click();
    await assertVisibleText(page, 'Missing location');
    assert.match(page.url(), /#\/quality\?issue=location/);
    await page.reload();
    await page.getByRole('button', { name: /Location/ }).waitFor();
    assert.match(page.url(), /#\/quality\?issue=location/);
    await page.getByRole('button', { name: /Needs recapture/ }).click();
    assert.match(page.url(), /#\/quality\?issue=recapture/);
    await page.getByRole('button', { name: 'Select in Jobs' }).click();
    await assertVisibleText(page, 'selected');
    await page.goto(`${base}/#/quality?issue=location`);
    await page.getByRole('button', { name: 'Dismiss visible' }).click();
    await assertVisibleText(page, 'dismissed');
    await page.getByRole('button', { name: /Reviewed/ }).click();
    await assertVisibleText(page, 'Undo reviewed');
    await page.getByRole('button', { name: 'Undo reviewed' }).click();
    await assertVisibleText(page, 'restored');

    assert.deepEqual(pageErrors, []);
    await page.close();
  });

  it('surfaces running and failed LLM queue details', async () => {
    const page = await browser.newPage();
    const pageErrors = [];
    page.on('pageerror', error => pageErrors.push(error.message));

    await page.goto(`${base}/#/llm-queue`);
    await assertVisibleText(page, 'LLM request queue');
    await assertVisibleText(page, 'Now running');
    await assertVisibleText(page, 'gemma-ui-test');
    await assertVisibleText(page, 'Request attempt');
    await assertVisibleText(page, 'Retry limit reached');
    await assertVisibleText(page, 'Reset + run');
    await page.getByRole('button', { name: /Failed/ }).click();
    await assertVisibleText(page, 'Retry limit reached');
    await page.getByRole('button', { name: /Running/ }).click();
    await assertVisibleText(page, 'Now running');
    await page.getByRole('button', { name: /All/ }).click();
    await page.getByRole('button', { name: 'Show details' }).first().click();
    await assertVisibleText(page, 'json_schema');
    await assertVisibleText(page, 'plain text');
    await page.getByRole('button', { name: /Open queue job #1/ }).click();
    await page.locator('.jh-panel').waitFor();
    assert.match(page.url(), /#\/jobs\/1/);
    await assertVisibleText(page, 'Capture diagnostics');

    assert.deepEqual(pageErrors, []);
    await page.close();
  });

  it('keeps duplicate actions keyboard reachable', async () => {
    const page = await browser.newPage();
    const pageErrors = [];
    page.on('pageerror', error => pageErrors.push(error.message));

    await page.goto(`${base}/#/duplicates`);
    const compareButton = page.getByRole('button', { name: 'Compare' }).first();
    await compareButton.focus();
    await page.keyboard.press('Enter');
    await assertVisibleText(page, 'Compare duplicate group');
    await page.getByRole('button', { name: 'Back' }).focus();
    await page.keyboard.press('Enter');
    await assertVisibleText(page, 'candidates');

    assert.deepEqual(pageErrors, []);
    await page.close();
  });

  it('supports keyboard row activation and returns focus after closing filter popovers', async () => {
    const page = await browser.newPage();
    const pageErrors = [];
    page.on('pageerror', error => pageErrors.push(error.message));

    await page.goto(`${base}/#/jobs`);
    await page.getByRole('columnheader', { name: 'Salary min' }).waitFor();

    const filterButton = page.getByRole('button', { name: 'Filter' });
    await filterButton.click();
    await page.keyboard.press('Escape');
    assert.equal(await filterButton.evaluate((el) => document.activeElement === el), true);

    const firstRow = page.locator('.jh-table tbody tr').first();
    await firstRow.focus();
    await page.keyboard.press('Enter');
    await page.locator('.jh-panel').waitFor();
    await assertVisibleText(page, 'Capture diagnostics');

    assert.deepEqual(pageErrors, []);
    await page.close();
  });

  it('sizes the app shell and jobs table to the viewport', async () => {
    const page = await browser.newPage();
    const pageErrors = [];
    page.on('pageerror', error => pageErrors.push(error.message));

    for (const size of [{ width: 1000, height: 640 }, { width: 1440, height: 900 }]) {
      await page.setViewportSize(size);
      await page.goto(`${base}/#/jobs`);
      await page.getByRole('columnheader', { name: 'Salary min' }).waitFor();

      const metrics = await page.evaluate(() => {
        const shell = document.querySelector('.jh-shell').getBoundingClientRect();
        const table = document.querySelector('.jh-tablewrap').getBoundingClientRect();
        return {
          viewportHeight: window.innerHeight,
          shellHeight: shell.height,
          tableBottom: table.bottom,
        };
      });

      assert.ok(Math.abs(metrics.shellHeight - metrics.viewportHeight) <= 1);
      assert.ok(Math.abs(metrics.tableBottom - metrics.viewportHeight) <= 1);
    }

    assert.deepEqual(pageErrors, []);
    await page.close();
  });

  it('shows capture diagnostics on the job detail panel', async () => {
    const page = await browser.newPage();
    const pageErrors = [];
    page.on('pageerror', error => pageErrors.push(error.message));

    await page.goto(`${base}/#/jobs/1`);
    await page.locator('.jh-panel').waitFor();
    await assertVisibleText(page, 'Capture diagnostics');
    await assertVisibleText(page, 'Selected text');
    await assertVisibleText(page, 'Structured data');
    await assertVisibleText(page, '1 item');
    await assertVisibleText(page, 'example.com/jobs/123?canonical=1');
    await assertVisibleText(page, 'Open source');
    await assertVisibleText(page, 'Re-run AI');
    await assertVisibleText(page, 'Mark unavailable');
    await assertVisibleText(page, 'Copy debug');
    await assertVisibleText(page, 'LLM · 91%');
    await assertVisibleText(page, 'LLM · 88%');

    await page.getByRole('tab', { name: 'Raw' }).click();
    await assertVisibleText(page, 'Canonical URL');
    await assertVisibleText(page, 'Visible size');

    assert.deepEqual(pageErrors, []);
    await page.close();
  });

  it('shows app-native dialog errors without browser alerts', async () => {
    const page = await browser.newPage();
    const pageErrors = [];
    page.on('pageerror', error => pageErrors.push(error.message));
    await page.route('**/api/jobs/bulk/status', route => route.fulfill({
      status: 500,
      contentType: 'text/plain',
      body: 'bulk status failed',
    }));

    await page.goto(`${base}/#/jobs`);
    await page.getByRole('columnheader', { name: 'Salary min' }).waitFor();
    await page.locator('.jh-table tbody input[type="checkbox"]').first().check();
    await page.getByRole('button', { name: 'Change status' }).first().click();
    await page.getByLabel('Archived').check();
    await page.getByRole('button', { name: 'Confirm' }).click();
    await assertVisibleText(page, 'bulk status failed');

    assert.deepEqual(pageErrors, []);
    await page.close();
  });

  it('renders jobs, split salary columns, and bulk status editing', async () => {
    const page = await browser.newPage();
    const pageErrors = [];
    page.on('pageerror', error => pageErrors.push(error.message));

    await page.goto(`${base}/#/jobs`);
    await page.getByRole('columnheader', { name: 'Salary min' }).waitFor();
    await page.getByRole('columnheader', { name: 'Salary max' }).waitFor();
    await assertVisibleText(page, 'Acme');
    await assertVisibleText(page, '$120k');
    await assertVisibleText(page, '$220k');
    const noCurrencyRow = page.getByRole('row').filter({ hasText: 'No Currency Co' });
    await noCurrencyRow.waitFor();
    await assertVisibleText(noCurrencyRow, '120k');
    await assertVisibleText(noCurrencyRow, '180k');
    assert.equal(await noCurrencyRow.getByText('$120k', { exact: false }).count(), 0);
    assert.equal(await noCurrencyRow.getByText('USD', { exact: false }).count(), 0);

    await page.getByLabel('Change status for job #1').selectOption('applied');
    await page.locator('.jh-chip[data-status="applied"]').first().waitFor();
    assert.equal(await page.locator('.jh-panel').count(), 0);

    const rowCheckboxes = page.locator('.jh-table tbody input[type="checkbox"]');
    await rowCheckboxes.nth(0).check();
    await rowCheckboxes.nth(1).check();
    await assertVisibleText(page, '2 selected');
    await page.getByRole('button', { name: 'Compare' }).first().click();
    await assertVisibleText(page, 'Compare selected jobs');
    await assertVisibleText(page, 'Warnings');
    await page.getByRole('button', { name: 'Close' }).click();
    await page.getByRole('button', { name: 'Queue AI' }).click();
    await assertVisibleText(page, 'Missing fields only');
    await assertVisibleText(page, 'Fit score only');
    await assertVisibleText(page, 'Full extraction');
    await page.getByRole('button', { name: 'Cancel' }).click();

    await page.getByRole('button', { name: 'Change status' }).first().click();
    await page.getByLabel('Archived').check();
    await page.getByRole('button', { name: 'Confirm' }).click();
    await assertVisibleText(page, '2 jobs updated to archived');

    const archived = page.locator('.jh-chip[data-status="archived"]');
    await archived.first().waitFor();
    assert.equal(await archived.count(), 2);
    assert.deepEqual(pageErrors, []);
    await page.close();
  });

  it('shows availability automation settings', async () => {
    const page = await browser.newPage();
    const pageErrors = [];
    page.on('pageerror', error => pageErrors.push(error.message));

    await page.goto(`${base}/#/settings`);
    await assertVisibleText(page, 'Availability checks');
    await assertVisibleText(page, 'Auto-check stale jobs');
    await assertVisibleText(page, 'Run at most every');
    await assertVisibleText(page, 'Consider stale after');

    assert.deepEqual(pageErrors, []);
    await page.close();
  });

  it('opens help documentation from the sidebar', async () => {
    const page = await browser.newPage();
    const pageErrors = [];
    page.on('pageerror', error => pageErrors.push(error.message));

    await page.goto(`${base}/#/jobs`);
    await page.getByRole('button', { name: 'Help' }).click();
    assert.match(page.url(), /#\/help/);
    await assertVisibleText(page, 'Operational guide');
    await assertVisibleText(page, 'Initial setup');
    await assertVisibleText(page, 'Capturing jobs');
    await assertVisibleText(page, 'AI extraction');
    await assertVisibleText(page, 'Troubleshooting');

    assert.deepEqual(pageErrors, []);
    await page.close();
  });
});

async function assertVisibleText(page, text) {
  await page.getByText(text, { exact: false }).first().waitFor();
}
