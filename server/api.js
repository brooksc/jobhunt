// Mirrors python/src/jobhunt/api.py
// Express app with all 38 API endpoints.

import express from 'express';
import { fileURLToPath } from 'url';
import { dirname, join, resolve } from 'path';
import { readFileSync, statSync, existsSync } from 'fs';
import { readdirSync } from 'fs';

import * as db from './db.js';
import { jobsCsv } from './export.js';
import { checkJobsAvailability, maybeRunStaleAvailabilityCheck } from './availability.js';
import {
  runExtraction, runExtractionForSelected,
  parseBoolSetting, makeExtractorFromSettings, makeScorerFromSettings,
  resolveProviderBaseUrl, ANTHROPIC_MODELS, GOOGLE_MODELS,
} from './extract.js';

const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);
const STATIC_DIR = resolve(__dirname, '../static');
const VERSION = '0.1.0';
const AUTO_EXTRACT_INTERVAL_MS = 5000;
const AUTO_AVAILABILITY_INTERVAL_MS = 60 * 60 * 1000;
const EXTENSION_WRITE_PATHS = new Set(['/captures', '/site-reviews']);

/** @param {{ dbPath?: string, autoExtract?: boolean }} [opts] */
export function createApp({ dbPath, autoExtract = false } = {}) {
  const app = express();

  app.use((req, res, next) => {
    if (!EXTENSION_WRITE_PATHS.has(req.path)) {
      return next();
    }

    const origin = req.get('origin');
    if (origin && origin.startsWith('chrome-extension://')) {
      res.set('Access-Control-Allow-Origin', origin);
      res.set('Access-Control-Allow-Headers', 'content-type');
      res.set('Access-Control-Allow-Methods', 'POST, OPTIONS');
      if (req.get('access-control-request-private-network') === 'true') {
        res.set('Access-Control-Allow-Private-Network', 'true');
      }
    }

    if (req.method === 'OPTIONS') {
      return res.sendStatus(204);
    }

    next();
  });

  app.use(express.json({ limit: '10mb' }));

  // No-cache for dynamic assets
  app.use((req, res, next) => {
    const p = req.path;
    if (p === '/' || p.endsWith('.jsx') || p.endsWith('.css') || p.endsWith('.html')) {
      res.set('Cache-Control', 'no-store, max-age=0, must-revalidate');
      res.set('Pragma', 'no-cache');
      res.set('Expires', '0');
    }
    next();
  });

  // Static files
  if (existsSync(STATIC_DIR)) {
    app.use('/static', express.static(STATIC_DIR));
  }

  // ------------------------------------------------------------------
  // Helpers
  // ------------------------------------------------------------------

  function getDbSettings() {
    const d = db.initDb(dbPath);
    return db.getSettings(d);
  }

  function buildExtractor(settings) {
    return makeExtractorFromSettings(settings);
  }

  function buildScorer(settings) {
    return makeScorerFromSettings(settings);
  }

  async function runExtractionForApp(limit) {
    const settings = getDbSettings();
    const extractor = buildExtractor(settings);
    const scorer = buildScorer(settings);
    return runExtraction({ dbPath, extractor, limit, scorer, resume: settings.resume_text || '' });
  }

  if (autoExtract) {
    globalThis.setInterval(() => {
      runExtractionForApp(10).catch(() => {});
    }, AUTO_EXTRACT_INTERVAL_MS).unref();
    globalThis.setInterval(() => {
      maybeRunStaleAvailabilityCheck(dbPath).catch(() => {});
    }, AUTO_AVAILABILITY_INTERVAL_MS).unref();
    maybeRunStaleAvailabilityCheck(dbPath).catch(() => {});
  }

  // ------------------------------------------------------------------
  // Health & root
  // ------------------------------------------------------------------

  app.get('/health', (req, res) => {
    res.json({ ok: true, service: 'jobhunt', version: VERSION });
  });

  // Used by the Chrome extension to discover which port the server is on
  app.get('/api/ping', (req, res) => {
    res.json({ app: 'jobhunt', version: VERSION });
  });

  app.get('/favicon.ico', (req, res) => {
    res.sendFile(join(STATIC_DIR, 'favicon.ico'));
  });

  app.get('/', (req, res) => {
    const indexPath = join(STATIC_DIR, 'index.html');
    if (!existsSync(indexPath)) {
      return res.status(503).send('Static files not found. Run: cp -r python/src/jobhunt/static ./static');
    }
    // Inject version hash for cache busting
    let html = readFileSync(indexPath, 'utf8');
    try {
      const v = maxMtime(STATIC_DIR, ['.jsx', '.css']).toString();
      html = html.replace(/\.jsx">/g, `.jsx?v=${v}">`).replace(/\.css">/g, `.css?v=${v}">`);
    } catch { /* leave html as-is */ }
    res.set('Content-Type', 'text/html').send(html);
  });

  function maxMtime(dir, exts) {
    let max = 0;
    function walk(d) {
      for (const entry of readdirSync(d, { withFileTypes: true })) {
        const p = join(d, entry.name);
        if (entry.isDirectory()) walk(p);
        else if (exts.some(e => entry.name.endsWith(e))) {
          const mt = statSync(p).mtimeMs;
          if (mt > max) max = mt;
        }
      }
    }
    walk(dir);
    return Math.floor(max);
  }

  // ------------------------------------------------------------------
  // UI data
  // ------------------------------------------------------------------

  app.get('/api/dashboard', (req, res) => {
    res.json(buildUiData(dbPath));
  });

  app.get('/api/ui-data', (req, res) => {
    res.json(buildUiData(dbPath));
  });

  // ------------------------------------------------------------------
  // CSV export
  // ------------------------------------------------------------------

  app.get('/exports/jobs.csv', (req, res) => {
    res.set('Content-Type', 'text/csv');
    res.set('Content-Disposition', 'attachment; filename=jobhunt-jobs.csv');
    res.send(jobsCsv(dbPath));
  });

  // ------------------------------------------------------------------
  // Captures
  // ------------------------------------------------------------------

  app.post('/captures', async (req, res) => {
    try {
      const capture = req.body;
      if (!capture.url || !capture.page_title) {
        return res.status(400).json({ error: 'url and page_title required' });
      }
      if (!capture.visible_text?.trim() && !capture.selected_text?.trim()) {
        return res.status(400).json({ error: 'visible_text or selected_text required' });
      }
      const result = db.insertCapture(capture, dbPath);
      if (autoExtract && !result.duplicate) {
        runExtractionForApp(10).catch(() => {});
      }
      res.json({ ok: true, capture_id: result.capture_id, duplicate: result.duplicate });
    } catch (err) {
      res.status(400).json({ error: String(err.message) });
    }
  });

  // ------------------------------------------------------------------
  // Availability check
  // ------------------------------------------------------------------

  app.post('/api/jobs/check-availability', async (req, res) => {
    try {
      const summary = await checkJobsAvailability(dbPath);
      res.json({ ok: true, ...summary });
    } catch (err) {
      res.status(500).json({ error: String(err.message) });
    }
  });

  // ------------------------------------------------------------------
  // LLM queue
  // ------------------------------------------------------------------

  app.post('/api/llm-queue/process-selected', async (req, res) => {
    try {
      const requestIds = req.body?.request_ids || [];
      let summary;
      if (!requestIds.length) {
        summary = await runExtractionForApp(100);
      } else {
        db.resetLlmRequestsForManualRun(dbPath, requestIds);
        const settings = getDbSettings();
        const extractor = buildExtractor(settings);
        const scorer = buildScorer(settings);
        summary = await runExtractionForSelected({ dbPath, extractor, requestIds, scorer, resume: settings.resume_text || '' });
      }
      res.json({ ok: true, ...summary });
    } catch (err) {
      res.status(500).json({ error: String(err.message) });
    }
  });

  app.post('/api/llm-queue/enqueue-all', (req, res) => {
    try {
      const enqueued = db.enqueueAllPendingJobs(dbPath);
      res.json({ ok: true, enqueued });
    } catch (err) {
      res.status(500).json({ error: String(err.message) });
    }
  });

  app.post('/api/extractions/run', async (req, res) => {
    try {
      const summary = await runExtractionForApp(100);
      res.json({ ok: true, ...summary });
    } catch (err) {
      res.status(500).json({ error: String(err.message) });
    }
  });

  app.get('/api/llm-queue', (req, res) => {
    try {
      const queueItems = db.getOutstandingLlmRequests(dbPath, ['queued', 'running', 'failed'], null);
      const unqueued = db.countUnqueuedPendingJobs(dbPath);
      const settings = getDbSettings();
      res.json({
        ok: true,
        items: queueItems,
        paused: parseBoolSetting(settings.llm_queue_paused, false),
        counts: {
          queued: queueItems.filter(i => i.status === 'queued').length,
          running: queueItems.filter(i => i.status === 'running').length,
          failed: queueItems.filter(i => i.status === 'failed').length,
          pending_unqueued: unqueued,
        },
      });
    } catch (err) {
      res.status(500).json({ error: String(err.message) });
    }
  });

  app.post('/api/llm-queue/pause', (req, res) => {
    try {
      const paused = req.body?.paused ?? false;
      const d = db.initDb(dbPath);
      db.setSetting(d, 'llm_queue_paused', paused ? 'true' : 'false');
      res.json({ ok: true, paused });
    } catch (err) {
      res.status(500).json({ error: String(err.message) });
    }
  });

  app.post('/api/llm-queue/cancel-all', (req, res) => {
    try {
      const canceled = db.cancelAllLlmRequests(dbPath, ['queued', 'running', 'failed']);
      res.json({ ok: true, canceled });
    } catch (err) {
      res.status(500).json({ error: String(err.message) });
    }
  });

  app.get('/api/llm-queue/:requestId/attempts', (req, res) => {
    try {
      res.json({ ok: true, attempts: db.getLlmRequestAttempts(dbPath, req.params.requestId) });
    } catch (err) {
      res.status(500).json({ error: String(err.message) });
    }
  });

  app.post('/api/llm-queue/:requestId/reset-run', async (req, res) => {
    try {
      const requestId = req.params.requestId;
      db.resetLlmRequestsForManualRun(dbPath, [requestId]);
      const settings = getDbSettings();
      const extractor = buildExtractor(settings);
      const scorer = buildScorer(settings);
      const summary = await runExtractionForSelected({
        dbPath,
        extractor,
        requestIds: [requestId],
        scorer,
        resume: settings.resume_text || '',
      });
      res.json({ ok: true, ...summary });
    } catch (err) {
      res.status(500).json({ error: String(err.message) });
    }
  });

  // Must be after all fixed-path /api/llm-queue/* routes to avoid shadowing
  app.post('/api/llm-queue/:requestId/cancel', (req, res) => {
    try {
      const removed = db.cancelLlmRequest(req.params.requestId, dbPath);
      if (!removed) return res.status(404).json({ error: 'Request not found or not eligible' });
      res.json({ ok: true });
    } catch (err) {
      res.status(500).json({ error: String(err.message) });
    }
  });

  // ------------------------------------------------------------------
  // Site reviews
  // ------------------------------------------------------------------

  app.post('/site-reviews', (req, res) => {
    try {
      const review = req.body;
      if (!review.site_url || !review.site_origin) {
        return res.status(400).json({ error: 'site_url and site_origin required' });
      }
      const siteReviewId = db.insertSiteReview(review, dbPath);
      res.json({ ok: true, site_review_id: siteReviewId });
    } catch (err) {
      res.status(400).json({ error: String(err.message) });
    }
  });

  app.post('/api/site-reviews/mark', (req, res) => {
    try {
      const siteReviewId = db.insertSiteReview(req.body, dbPath);
      res.json({ ok: true, site_review_id: siteReviewId });
    } catch (err) {
      res.status(400).json({ error: String(err.message) });
    }
  });

  // ------------------------------------------------------------------
  // Jobs
  // ------------------------------------------------------------------

  app.patch('/api/jobs/bulk/status', (req, res) => {
    try {
      const result = db.updateJobStatuses(req.body.job_ids, req.body.status, dbPath);
      res.json({ ok: true, ...result });
    } catch (err) {
      res.status(400).json({ error: String(err.message) });
    }
  });

  app.post('/api/jobs/bulk/data-quality-reviewed', (req, res) => {
    try {
      const result = db.markDataQualityReviewed(req.body.job_ids, req.body.note, dbPath);
      res.json({ ok: true, ...result });
    } catch (err) {
      res.status(400).json({ error: String(err.message) });
    }
  });

  app.delete('/api/jobs/bulk/data-quality-reviewed', (req, res) => {
    try {
      const result = db.clearDataQualityReviewed(req.body.job_ids, dbPath);
      res.json({ ok: true, ...result });
    } catch (err) {
      res.status(400).json({ error: String(err.message) });
    }
  });

  app.post('/api/jobs/bulk/llm', (req, res) => {
    try {
      const result = db.queueBulkLlmJobs(req.body.job_ids, req.body.mode, dbPath);
      if (autoExtract) runExtractionForApp(100).catch(() => {});
      res.json({ ok: true, ...result });
    } catch (err) {
      res.status(400).json({ error: String(err.message) });
    }
  });

  app.post('/api/jobs/bulk/llm-by-number', (req, res) => {
    try {
      const result = db.queueBulkLlmJobsByNumbers(req.body.job_numbers, req.body.mode, dbPath);
      if (autoExtract) runExtractionForApp(100).catch(() => {});
      res.json({ ok: true, ...result });
    } catch (err) {
      res.status(400).json({ error: String(err.message) });
    }
  });

  app.patch('/api/jobs/:jobId/status', (req, res) => {
    try {
      db.updateJobStatus(req.params.jobId, req.body.status, dbPath);
      res.json({ ok: true });
    } catch (err) {
      res.status(400).json({ error: String(err.message) });
    }
  });

  app.post('/api/jobs/:jobId/notes', (req, res) => {
    try {
      db.addJobNote(req.params.jobId, req.body.note, dbPath);
      res.json({ ok: true });
    } catch (err) {
      res.status(400).json({ error: String(err.message) });
    }
  });

  app.post('/api/jobs/:jobId/archive', (req, res) => {
    try {
      db.updateJobStatus(req.params.jobId, 'archived', dbPath);
      res.json({ ok: true });
    } catch (err) {
      res.status(400).json({ error: String(err.message) });
    }
  });

  app.patch('/api/jobs/:jobId', (req, res) => {
    try {
      const d = db.initDb(dbPath);
      db.updateJobFields(d, req.params.jobId, req.body);
      res.json({ ok: true });
    } catch (err) {
      res.status(400).json({ error: String(err.message) });
    }
  });

  app.patch('/api/jobs/:jobId/skills', (req, res) => {
    try {
      const d = db.initDb(dbPath);
      db.updateJobSkills(d, req.params.jobId, req.body.skills || []);
      res.json({ ok: true });
    } catch (err) {
      res.status(400).json({ error: String(err.message) });
    }
  });

  app.patch('/api/jobs/:jobId/rating', (req, res) => {
    try {
      const d = db.initDb(dbPath);
      db.setJobRating(d, req.params.jobId, req.body.rating ?? null);
      res.json({ ok: true });
    } catch (err) {
      res.status(400).json({ error: String(err.message) });
    }
  });

  app.post('/api/jobs/:jobId/extract', async (req, res) => {
    try {
      const requestId = db.resetJobExtraction(req.params.jobId, dbPath);
      if (autoExtract) runExtractionForApp(100).catch(() => {});
      res.json({ ok: true, request_id: requestId });
    } catch (err) {
      res.status(400).json({ error: String(err.message) });
    }
  });

  app.post('/api/jobs/:jobId/fit-score', async (req, res) => {
    try {
      const d = db.initDb(dbPath);
      const settings = db.getSettings(d);
      const row = d.prepare("SELECT extraction_status FROM jobs WHERE id=?").get(req.params.jobId);
      if (!row) return res.status(400).json({ error: 'job not found' });
      if (!String(settings.resume_text || '').trim()) {
        return res.status(400).json({ error: 'Add your resume in Settings before scoring fit.' });
      }
      if (row.extraction_status !== 'succeeded') {
        return res.status(400).json({ error: 'Extract this job before scoring fit.' });
      }
      db.queueFitScoreForJob(dbPath, req.params.jobId, { resetAttempts: true });
      if (autoExtract) runExtractionForApp(100).catch(() => {});
      res.json({ ok: true });
    } catch (err) {
      res.status(400).json({ error: String(err.message) });
    }
  });

  // ------------------------------------------------------------------
  // Actions
  // ------------------------------------------------------------------

  app.post('/api/jobs/:jobId/actions', (req, res) => {
    try {
      const d = db.initDb(dbPath);
      const action = db.createNextAction(d, req.params.jobId, req.body.note, req.body.due_date);
      res.json(action);
    } catch (err) {
      res.status(400).json({ error: String(err.message) });
    }
  });

  app.get('/api/jobs/:jobId/actions', (req, res) => {
    try {
      const d = db.initDb(dbPath);
      const action = db.getActiveAction(d, req.params.jobId);
      res.json(action || {});
    } catch (err) {
      res.status(500).json({ error: String(err.message) });
    }
  });

  app.post('/api/actions/:actionId/complete', (req, res) => {
    try {
      const d = db.initDb(dbPath);
      db.completeAction(d, req.params.actionId);
      res.json({ ok: true });
    } catch (err) {
      const status = err.message.includes('not found') ? 404 : 500;
      res.status(status).json({ error: String(err.message) });
    }
  });

  app.post('/api/actions/:actionId/snooze', (req, res) => {
    try {
      const d = db.initDb(dbPath);
      const action = db.snoozeAction(d, req.params.actionId, req.body.days ?? 7);
      res.json(action);
    } catch (err) {
      const status = err.message.includes('not found') ? 404 : 500;
      res.status(status).json({ error: String(err.message) });
    }
  });

  // ------------------------------------------------------------------
  // Sites
  // ------------------------------------------------------------------

  app.get('/api/sites', (req, res) => {
    try {
      const d = db.initDb(dbPath);
      res.json(db.getSites(d));
    } catch (err) {
      res.status(500).json({ error: String(err.message) });
    }
  });

  app.post('/api/sites', (req, res) => {
    try {
      const body = req.body;
      let origin = body.origin;
      if (!origin) {
        try {
          const parsed = new URL(body.url);
          origin = `${parsed.protocol}//${parsed.host}`;
        } catch {
          origin = body.url;
        }
      }
      const d = db.initDb(dbPath);
      const settings = db.getSettings(d);
      const intervalDays = body.interval_days != null ? body.interval_days : parseInt(settings.site_review_interval_days || '14');
      const site = db.addSite(d, {
        origin, url: body.url, pageTitle: body.page_title || '',
        state: body.state || 'not_reviewed', companyName: body.company_name || null,
        companyWebsite: body.company_website || null, jobsUrl: body.jobs_url || null,
        companyDescription: body.company_description || '', addedAt: body.added_at || null,
        intervalDays, note: body.note || '',
      });
      res.json(site);
    } catch (err) {
      res.status(400).json({ error: String(err.message) });
    }
  });

  app.post('/api/sites/:siteId/review', (req, res) => {
    try {
      const d = db.initDb(dbPath);
      const row = db.resolveSite(d, req.params.siteId);
      if (!row) return res.status(404).json({ error: `Site not found: ${req.params.siteId}` });
      const site = db.reviewSiteRow(d, row);
      res.json(site);
    } catch (err) {
      res.status(500).json({ error: String(err.message) });
    }
  });

  app.post('/api/sites/review', (req, res) => {
    try {
      const siteRef = req.body.site_ref;
      const d = db.initDb(dbPath);
      const row = db.resolveSite(d, siteRef);
      if (!row) return res.status(404).json({ error: `Site not found: ${siteRef}` });
      const site = db.reviewSiteRow(d, row);
      res.json(site);
    } catch (err) {
      res.status(500).json({ error: String(err.message) });
    }
  });

  app.patch('/api/sites/:siteId', (req, res) => {
    try {
      const body = req.body;
      const d = db.initDb(dbPath);
      const row = db.resolveSite(d, req.params.siteId);
      if (!row) return res.status(404).json({ error: `Site not found: ${req.params.siteId}` });
      const resolvedId = row.id;
      const resolvedOrigin = row.origin;
      const nowIso = new Date().toISOString().replace(/\.\d{3}Z$/, 'Z');
      const pkCol = resolvedId ? 'id' : 'origin';
      const pkVal = resolvedId || resolvedOrigin;

      if (body.next_review_days != null && resolvedId) {
        db.setSiteNextReview(d, resolvedId, body.next_review_days);
      } else if (body.interval_days != null && resolvedId) {
        db.setSiteNextReview(d, resolvedId, body.interval_days);
      }
      if (body.note != null) {
        if (resolvedId) db.updateSiteNote(d, resolvedId, body.note);
        else d.prepare(`UPDATE sites SET note=?, updated_at=? WHERE origin=?`).run(body.note, nowIso, resolvedOrigin);
      }
      for (const [col, val] of [['url', body.url], ['company_name', body.company_name], ['company_website', body.company_website], ['jobs_url', body.jobs_url], ['company_description', body.company_description]]) {
        if (val != null) d.prepare(`UPDATE sites SET ${col}=?, updated_at=? WHERE ${pkCol}=?`).run(val, nowIso, pkVal);
      }
      if (body.state != null) {
        if (resolvedId) db.setSiteState(d, resolvedId, body.state);
        else db.setSiteStateForOrigin(d, resolvedOrigin, body.state);
      }
      const site = resolvedId
        ? d.prepare("SELECT * FROM sites WHERE id=?").get(resolvedId)
        : d.prepare("SELECT * FROM sites WHERE origin=?").get(resolvedOrigin);
      res.json(site);
    } catch (err) {
      res.status(500).json({ error: String(err.message) });
    }
  });

  app.delete('/api/sites/:siteId', (req, res) => {
    try {
      const d = db.initDb(dbPath);
      const row = db.resolveSite(d, req.params.siteId);
      if (!row) return res.status(404).json({ error: `Site not found: ${req.params.siteId}` });
      if (!row.id) d.prepare("DELETE FROM sites WHERE origin=?").run(row.origin);
      else db.deleteSite(d, row.id);
      res.json({ ok: true });
    } catch (err) {
      res.status(500).json({ error: String(err.message) });
    }
  });

  // ------------------------------------------------------------------
  // Duplicates
  // ------------------------------------------------------------------

  app.post('/api/duplicates/decision', (req, res) => {
    try {
      const { cleaned_hash, decision, keep_job_id, note } = req.body;
      db.decideDuplicateGroup(cleaned_hash, decision, keep_job_id, note || '', dbPath);
      res.json({ ok: true });
    } catch (err) {
      res.status(400).json({ error: String(err.message) });
    }
  });

  // ------------------------------------------------------------------
  // Settings
  // ------------------------------------------------------------------

  app.get('/api/settings', (req, res) => {
    res.json(getDbSettings());
  });

  app.patch('/api/settings', (req, res) => {
    try {
      const d = db.initDb(dbPath);
      const allowed = new Set(Object.keys(db.SETTINGS_DEFAULTS));
      for (const [key, val] of Object.entries(req.body)) {
        if (!allowed.has(key)) continue;
        if (val != null) db.setSetting(d, key, String(val));
      }
      res.json({ ok: true });
    } catch (err) {
      res.status(500).json({ error: String(err.message) });
    }
  });

  app.post('/api/settings/test-llm', async (req, res) => {
    try {
      const settings = getDbSettings();
      const provider = req.body?.provider || settings.llm_provider || 'lmstudio';
      const apiKey = req.body?.api_key || settings.llm_api_key || '';
      const model = req.body?.model || settings.llm_model || '';
      const rawBaseUrl = req.body?.base_url || settings.llm_base_url || 'http://127.0.0.1:1234';

      // Providers with hardcoded model lists — no connectivity needed for quick mode
      if (provider === 'anthropic') {
        if (req.body?.quick) return res.json({ ok: true, models: ANTHROPIC_MODELS });
        // Full test: skip OpenAI-specific capability tests; just verify connectivity
        return res.json({
          ok: true, models: ANTHROPIC_MODELS,
          modelTests: [{ name: 'Provider', status: 'pass', message: 'Anthropic — uses native Messages API' }],
        });
      }
      if (provider === 'google') {
        if (req.body?.quick) return res.json({ ok: true, models: GOOGLE_MODELS });
        return res.json({
          ok: true, models: GOOGLE_MODELS,
          modelTests: [{ name: 'Provider', status: 'pass', message: 'Google Gemini — uses native generateContent API' }],
        });
      }

      // OpenAI-compatible providers (lmstudio, openai, openrouter, custom)
      const baseUrl = resolveProviderBaseUrl(provider, rawBaseUrl);
      const connHeaders = /** @type {Record<string,string>} */ ({});
      if (apiKey) connHeaders['Authorization'] = `Bearer ${apiKey}`;

      // Step 1: connectivity + model list (5s timeout)
      let modelIds = [];
      const connController = new AbortController();
      const connTimer = setTimeout(() => connController.abort(), 5000);
      try {
        const response = await fetch(`${baseUrl}/v1/models`, { headers: connHeaders, signal: connController.signal });
        if (!response.ok) return res.json({ ok: false, error: `HTTP ${response.status}` });
        const data = /** @type {any} */ (await response.json());
        modelIds = (data.data || []).map(m => m.id || '').filter(Boolean);
      } catch (e) {
        return res.json({ ok: false, error: e.name === 'AbortError' ? 'Connection timed out' : String(e.message) });
      } finally {
        clearTimeout(connTimer);
      }

      if (req.body?.quick) return res.json({ ok: true, models: modelIds });

      // Step 2: run model capability tests — only if the configured model is actually loaded
      const resolvedModel = model || modelIds[0] || '';
      const providerLabel = provider === 'lmstudio' ? 'LM Studio' : provider === 'openai' ? 'OpenAI' : provider === 'openrouter' ? 'OpenRouter' : 'server';
      if (resolvedModel && modelIds.length > 0 && !modelIds.includes(resolvedModel)) {
        return res.json({
          ok: true, models: modelIds,
          modelTests: [{ name: 'Capability tests', status: 'fail', message: `Skipped — model "${resolvedModel}" is not loaded in ${providerLabel}` }],
        });
      }
      const modelTests = await runModelTests(baseUrl, resolvedModel, apiKey);
      res.json({ ok: true, models: modelIds, modelTests });
    } catch (err) {
      res.json({ ok: false, error: String(err.message) });
    }
  });

  return app;
}

// ------------------------------------------------------------------
// Model capability tests
// ------------------------------------------------------------------

function makeSyntheticJd(targetChars = 10000) {
  const block = `Senior Software Engineer – Platform Infrastructure
Company: Acme Corp | Seattle, WA | Hybrid | $180k–$240k + equity

About the role: Join the Platform Infrastructure team building the systems that power our core product and support hundreds of engineers. You will own design, implementation, and operations of distributed services at scale.

Responsibilities:
- Design and build distributed systems (queues, caches, data pipelines)
- Lead projects from RFC through production rollout
- Define SLOs, own on-call rotation, drive post-mortems
- Mentor engineers and conduct design/code reviews
- Partner with product to scope and estimate platform investments

Required: 5+ years SWE experience · distributed systems · Python or Go · AWS/GCP/Azure · SQL and NoSQL databases · Docker/Kubernetes · strong communication skills

Preferred: Internal developer platforms · observability (Prometheus, Grafana, OpenTelemetry) · infrastructure-as-code (Terraform, Pulumi) · experience in high-growth environments

Benefits: Equity · medical/dental/vision · 401k match · flexible PTO · $2k learning budget`;
  let out = '';
  while (out.length < targetChars) out += block + '\n\n';
  return out.slice(0, targetChars);
}

async function chatCompletion(baseUrl, model, messages, extra = {}, timeoutMs = 15000, apiKey = '') {
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), timeoutMs);
  const headers = /** @type {Record<string,string>} */ ({ 'Content-Type': 'application/json' });
  if (apiKey) headers['Authorization'] = `Bearer ${apiKey}`;
  try {
    const res = await fetch(`${baseUrl}/v1/chat/completions`, {
      method: 'POST',
      headers,
      body: JSON.stringify({ model, messages, temperature: 0, stream: false, ...extra }),
      signal: controller.signal,
    });
    return { res, data: res.ok ? /** @type {any} */ (await res.json()) : null, errorText: res.ok ? null : await res.text() };
  } catch (e) {
    return { res: null, data: null, errorText: e.name === 'AbortError' ? 'timeout' : String(e.message) };
  } finally {
    clearTimeout(timer);
  }
}

/** @returns {Promise<{name:string, status:'pass'|'fail'|'warn', message:string}>} */
async function testJsonSchema(baseUrl, model, apiKey = '') {
  const name = 'JSON schema mode';
  const schema = {
    type: 'object',
    properties: { title: { type: 'string' }, company: { type: 'string' } },
    required: ['title', 'company'],
    additionalProperties: false,
  };
  const { res, data, errorText } = await chatCompletion(baseUrl, model, [
    { role: 'system', content: 'Extract job info from the posting.' },
    { role: 'user', content: 'Job: Senior Engineer at Acme Corp in Seattle.' },
  ], {
    max_tokens: 64,
    response_format: { type: 'json_schema', json_schema: { name: 'job', strict: true, schema } },
  }, 15000, apiKey);

  if (errorText === 'timeout') return { name, status: 'fail', message: 'Timed out' };
  if (!res?.ok) return { name, status: 'warn', message: `Not supported (HTTP ${res?.status}) — extraction will fall back to json_object mode` };
  const content = String(data?.choices?.[0]?.message?.content || '');
  try {
    const parsed = JSON.parse(content);
    if (parsed.title && parsed.company) return { name, status: 'pass', message: `Supported · returned {title, company}` };
    return { name, status: 'warn', message: `Accepted but response missing expected fields: ${content.slice(0, 100)}` };
  } catch {
    return { name, status: 'warn', message: `Accepted but response is not valid JSON: ${content.slice(0, 100)}` };
  }
}

/** @returns {Promise<{name:string, status:'pass'|'fail'|'warn', message:string}>} */
async function testJsonObject(baseUrl, model, apiKey = '') {
  const name = 'JSON object mode';
  const { res, data, errorText } = await chatCompletion(baseUrl, model, [
    { role: 'system', content: 'You must reply with valid JSON only.' },
    { role: 'user', content: 'Return a JSON object with key "status" set to "ok".' },
  ], { max_tokens: 32, response_format: { type: 'json_object' } }, 15000, apiKey);

  if (errorText === 'timeout') return { name, status: 'fail', message: 'Timed out' };
  if (!res?.ok) return { name, status: 'fail', message: `Not supported (HTTP ${res?.status}) — extraction will rely on prompt-only JSON and jsonrepair` };
  const content = String(data?.choices?.[0]?.message?.content || '');
  try {
    JSON.parse(content);
    return { name, status: 'pass', message: 'Supported · response is valid JSON' };
  } catch {
    return { name, status: 'warn', message: `Accepted but response is not valid JSON: ${content.slice(0, 100)}` };
  }
}

/** @returns {Promise<{name:string, status:'pass'|'fail'|'warn', message:string}>} */
async function testContextLength(baseUrl, model, apiKey = '') {
  const name = 'Context length (~2500 tokens)';
  if (!model) return { name, status: 'fail', message: 'No model selected' };

  const syntheticJd = makeSyntheticJd(10000);
  const t0 = Date.now();
  const { res, data, errorText } = await chatCompletion(baseUrl, model, [
    { role: 'system', content: 'Extract job info. Reply ONLY with valid JSON: {"title":"...","company":"..."}' },
    { role: 'user', content: `Extract from this job posting:\n\n${syntheticJd}` },
  ], { max_tokens: 64 }, 30000, apiKey);

  if (errorText === 'timeout') return { name, status: 'fail', message: 'Timed out after 30s — model may be overloaded or context window too small' };
  if (!res?.ok) {
    const snippet = (errorText || '').slice(0, 150);
    return { name, status: 'fail', message: `Model rejected request (HTTP ${res?.status}) — context window too small. ${snippet}` };
  }

  const choice = data?.choices?.[0];
  if (choice?.finish_reason === 'length') {
    return { name, status: 'fail', message: 'Output was truncated (finish_reason=length) — max_tokens too low' };
  }

  const content = String(choice?.message?.content || '');
  if (!content.includes('{')) {
    return { name, status: 'warn', message: `Responded but without JSON: "${content.slice(0, 100)}"` };
  }

  const elapsed = ((Date.now() - t0) / 1000).toFixed(1);
  const tokensOut = data?.usage?.completion_tokens;
  const speed = tokensOut ? ` · ~${Math.round(tokensOut / ((Date.now() - t0) / 1000))} tok/s` : '';
  return { name, status: 'pass', message: `Handled ~2500-token input in ${elapsed}s${speed}` };
}

async function runModelTests(baseUrl, model, apiKey = '') {
  // Run sequentially — never two LLM requests in parallel
  const results = [];
  results.push(await testJsonSchema(baseUrl, model, apiKey));
  results.push(await testJsonObject(baseUrl, model, apiKey));
  results.push(await testContextLength(baseUrl, model, apiKey));
  return results;
}

// ------------------------------------------------------------------
// UI data builder
// ------------------------------------------------------------------

function buildUiData(dbPath) {
  const d = db.initDb(dbPath);
  const settingsData = db.getSettings(d);

  const jobRows = d.prepare(`SELECT jobs.id AS job_id, jobs.job_number, jobs.capture_id,
    jobs.status, jobs.extraction_status, jobs.extraction_error, jobs.company, jobs.title,
    jobs.location, jobs.remote_type, jobs.salary_min, jobs.salary_max, jobs.salary_currency,
    jobs.salary_note, jobs.extracted_json, jobs.extracted_at, jobs.fit_score, jobs.fit_status,
    jobs.fit_score_json, jobs.rating, jobs.duplicate_of_job_id, jobs.extraction_model,
    jobs.application_url, jobs.extraction_confidence, jobs.manual_overrides,
    captures.cleaned_description, captures.raw_hash, captures.cleaned_hash, captures.page_title,
    captures.selected_text, captures.visible_text, captures.structured_data_json,
    captures.url AS source_url, captures.canonical_url, captures.captured_at,
    data_quality_reviews.reviewed_at AS data_quality_reviewed_at,
    COALESCE(NULLIF(captures.selected_text,''), captures.visible_text) AS raw_text
    FROM jobs JOIN captures ON captures.id=jobs.capture_id
    LEFT JOIN data_quality_reviews ON data_quality_reviews.job_id=jobs.id
    ORDER BY captures.captured_at DESC`).all();

  const jobIds = jobRows.map(r => r.job_id);
  const eventsByJob = Object.fromEntries(jobIds.map(id => [id, []]));
  if (jobIds.length) {
    const placeholders = jobIds.map(() => '?').join(',');
    const eventRows = d.prepare(`SELECT job_id, event_type, note, occurred_at FROM events WHERE job_id IN (${placeholders}) ORDER BY occurred_at ASC`).all(...jobIds);
    for (const ev of eventRows) {
      if (eventsByJob[ev.job_id]) eventsByJob[ev.job_id].push({ event_type: ev.event_type, note: ev.note, occurred_at: ev.occurred_at });
    }
  }

  const siteRows = db.getSites(d);
  const activeActionsRows = d.prepare("SELECT * FROM job_actions WHERE completed_at IS NULL").all();
  const actionsByJob = {};
  for (const row of activeActionsRows) actionsByJob[row.job_id] = row;
  const needsActionCount = db.getNeedsActionCount(d);

  const dupRows = d.prepare(`SELECT captures.cleaned_hash, jobs.id AS job_id
    FROM captures JOIN jobs ON jobs.capture_id=captures.id
    LEFT JOIN duplicate_decisions ON duplicate_decisions.cleaned_hash=captures.cleaned_hash
    WHERE captures.cleaned_hash IN (
      SELECT cleaned_hash FROM captures WHERE cleaned_hash IS NOT NULL
      GROUP BY cleaned_hash HAVING COUNT(DISTINCT COALESCE(canonical_url, url)) > 1
    ) AND duplicate_decisions.cleaned_hash IS NULL ORDER BY captures.cleaned_hash`).all();

  const dupGroups = {};
  for (const row of dupRows) {
    if (!dupGroups[row.cleaned_hash]) dupGroups[row.cleaned_hash] = [];
    dupGroups[row.cleaned_hash].push(row.job_id);
  }
  const dupes = Object.entries(dupGroups).map(([h, ids], i) => ({ group_id: `g-${i}`, cleaned_hash: h, job_ids: ids }));

  const jobs = jobRows.map(r => {
    let extractedJson = r.extracted_json;
    if (extractedJson && typeof extractedJson === 'string') {
      try { extractedJson = JSON.parse(extractedJson); } catch { extractedJson = null; }
    }
    let fitScoreJson = r.fit_score_json;
    if (fitScoreJson && typeof fitScoreJson === 'string') {
      try { fitScoreJson = JSON.parse(fitScoreJson); } catch { fitScoreJson = null; }
    }
    const rawText = r.raw_text || '';
    let structuredDataCount = 0;
    if (r.structured_data_json) {
      try {
        const parsed = JSON.parse(r.structured_data_json);
        structuredDataCount = Array.isArray(parsed) ? parsed.length : 1;
      } catch {
        structuredDataCount = 0;
      }
    }
    return {
      job_id: r.job_id, job_number: r.job_number, status: r.status,
      extraction_status: r.extraction_status, extraction_error: r.extraction_error,
      company: r.company, title: r.title, location: r.location, remote_type: r.remote_type,
      salary_min: r.salary_min, salary_max: r.salary_max, salary_currency: r.salary_currency,
      salary_note: r.salary_note, extracted_json: extractedJson, extracted_at: r.extracted_at,
      fit_score: r.fit_score, fit_status: r.fit_status, fit_score_json: fitScoreJson,
      rating: r.rating, duplicate_of_job_id: r.duplicate_of_job_id,
      extraction_model: r.extraction_model, application_url: r.application_url,
      extraction_confidence: r.extraction_confidence, cleaned_description: r.cleaned_description,
      manual_overrides: r.manual_overrides,
      raw_hash: r.raw_hash, cleaned_hash: r.cleaned_hash,
      raw_byte_size: Buffer.byteLength(rawText, 'utf8'),
      visible_byte_size: Buffer.byteLength(r.visible_text || '', 'utf8'),
      cleaned_byte_size: Buffer.byteLength(r.cleaned_description || '', 'utf8'),
      selected_text_present: Boolean((r.selected_text || '').trim()),
      structured_data_count: structuredDataCount,
      page_title: r.page_title, source_url: r.source_url, canonical_url: r.canonical_url, captured_at: r.captured_at,
      data_quality_reviewed_at: r.data_quality_reviewed_at,
      raw_text: rawText, events: eventsByJob[r.job_id] || [],
      next_action: actionsByJob[r.job_id] || null,
    };
  });

  const metrics = buildMetrics(jobs, siteRows, dupes, needsActionCount);
  const resolvedDbPath = dbPath || db.defaultDbPath();

  return {
    jobs, sites: siteRows, dupes, metrics,
    meta: { total_jobs: jobs.length, loaded_jobs: jobs.length, total_sites: siteRows.length, loaded_sites: siteRows.length },
    settings: {
      version: VERSION,
      db_path: String(resolvedDbPath),
      config_dir: db.appConfigDir(),
      llm_debug_log_path: db.defaultLlmDebugLogPath(),
      server_url: 'http://127.0.0.1:8765',
      llm_provider: settingsData.llm_provider || 'lmstudio',
      llm_base_url: settingsData.llm_base_url,
      llm_api_key: settingsData.llm_api_key || '',
      llm_model: settingsData.llm_model,
      site_review_interval_days: parseInt(settingsData.site_review_interval_days || '14'),
      followup_default_days: parseInt(settingsData.followup_default_days || '7'),
      job_description_markdown: settingsData.job_description_markdown || '',
      resume_text: settingsData.resume_text || '',
      llm_queue_paused: settingsData.llm_queue_paused || 'false',
      llm_debug_level: settingsData.llm_debug_level || 'errors',
      preferred_locations: settingsData.preferred_locations || '',
      location_allow_remote: settingsData.location_allow_remote || 'true',
      location_allow_hybrid: settingsData.location_allow_hybrid || 'true',
      location_allow_onsite: settingsData.location_allow_onsite || 'true',
    },
  };
}

const DB_STATUS_TO_UI = { interested: 'saved', interviewing: 'interview', closed: 'archived', ignored: 'archived' };

function buildMetrics(jobs, sites, dupes, needsActionCount) {
  const counts = { saved: 0, applied: 0, interview: 0, offers: 0, rejected: 0, archived: 0, pendingExtraction: 0, failedExtraction: 0 };
  for (const job of jobs) {
    const status = DB_STATUS_TO_UI[job.status] || job.status;
    if (status === 'saved') counts.saved++;
    else if (status === 'applied') counts.applied++;
    else if (status === 'interview') counts.interview++;
    else if (status === 'offer') counts.offers++;
    else if (status === 'rejected') counts.rejected++;
    else if (status === 'archived') counts.archived++;
    if (job.extraction_status === 'pending') counts.pendingExtraction++;
    else if (job.extraction_status === 'failed') counts.failedExtraction++;
  }
  const now = new Date();
  let sitesDue = 0;
  for (const site of sites) {
    if (!site.next_review_at) continue;
    try {
      const due = new Date(site.next_review_at);
      if (due <= new Date(now.getTime() + 86400000)) sitesDue++;
    } catch { /* skip */ }
  }
  return {
    ...counts,
    sitesDue,
    duplicateCandidates: dupes.reduce((n, d) => n + d.job_ids.length, 0),
    duplicateGroups: dupes.length,
    needsAction: needsActionCount,
    jobs: jobs.length,
    sites: sites.length,
  };
}
