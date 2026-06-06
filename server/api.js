// Mirrors python/src/jobhunt/api.py
// Express app with all 38 API endpoints.

import express from 'express';
import { fileURLToPath } from 'url';
import { dirname, join, resolve } from 'path';
import { readFileSync, statSync, existsSync } from 'fs';
import { readdirSync } from 'fs';
import { isIP } from 'net';

import * as db from './db.js';
import { jobsCsv } from './export.js';
import { checkJobsAvailability, maybeRunStaleAvailabilityCheck } from './availability.js';
import { METRO_DATA } from './metros.js';
import {
  runExtraction, runExtractionForSelected,
  parseBoolSetting, makeExtractorFromSettings, makeScorerFromSettings,
  resolveProviderBaseUrl, resolveApiKey,
  MAX_DESCRIPTION_CHARS, MAX_RESUME_CHARS, promptOverheadChars, refreshRotationPool, fetchFreeModelIds,
  generateCoverLetter,
} from './extract.js';

const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);
const STATIC_DIR = resolve(__dirname, '../static');
const VERSION = JSON.parse(readFileSync(resolve(__dirname, '../package.json'), 'utf8')).version;
const AUTO_EXTRACT_INTERVAL_MS = 5000;
const AUTO_AVAILABILITY_INTERVAL_MS = 60 * 60 * 1000;
const EXTENSION_WRITE_PATHS = new Set(['/captures', '/site-reviews']);
const PRIVATE_IPV4_RANGES = [
  { pattern: /^10\./, label: 'private network' },
  { pattern: /^127\./, label: 'localhost' },
  { pattern: /^169\.254\./, label: 'link-local network' },
  { pattern: /^172\.(1[6-9]|2\d|3[0-1])\./, label: 'private network' },
  { pattern: /^192\.168\./, label: 'private network' },
];

function validateFetchableCaptureUrl(value) {
  let parsed;
  try {
    parsed = new URL(String(value || ''));
  } catch {
    throw new Error('valid http(s) url required');
  }
  if (parsed.protocol !== 'http:' && parsed.protocol !== 'https:') {
    throw new Error('only http(s) URLs can be captured');
  }
  const host = parsed.hostname.toLowerCase();
  if (host === 'localhost' || host.endsWith('.localhost')) {
    throw new Error('localhost URLs cannot be captured from the server');
  }
  if (host === '0.0.0.0' || host === '::' || host === '::1' || host === '[::1]' || host === '[::0]') {
    throw new Error('local URLs cannot be captured from the server');
  }
  if (isIP(host) === 4) {
    for (const range of PRIVATE_IPV4_RANGES) {
      if (range.pattern.test(host)) throw new Error(`${range.label} URLs cannot be captured from the server`);
    }
  }
  if (isIP(host) === 6) {
    if (host === '::1' || host.startsWith('fc') || host.startsWith('fd') || host.startsWith('fe80')) {
      throw new Error('local IPv6 URLs cannot be captured from the server');
    }
  }
  return parsed.toString();
}

/** @param {{ dbPath?: string, autoExtract?: boolean, demoDemoPath?: string }} [opts] */
export function createApp({ dbPath: initialDbPath, autoExtract = false, demoDemoPath } = {}) {
  let dbPath = initialDbPath;
  let isDemo = false;
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
    await refreshRotationPool(settings);
    const extractor = buildExtractor(settings);
    const scorer = buildScorer(settings);
    const summary = await runExtraction({ dbPath, extractor, limit, scorer });
    emitAiRunComplete(summary);
    return summary;
  }

  function emitAiRunComplete(summary) {
    if (summary?.processed > 0) {
      process.emit('jobhunt:ai-processing-complete', summary);
    }
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
    res.json({ app: 'jobhunt', version: VERSION, isDemo });
  });

  app.post('/api/db/switch', async (req, res) => {
    const { mode } = req.body || {};
    try {
      if (mode === 'demo') {
        if (!demoDemoPath) return res.status(400).json({ error: 'Demo DB not configured' });
        const { ensureDemoDb } = await import('./demo.js');
        ensureDemoDb(demoDemoPath);
        dbPath = demoDemoPath;
        isDemo = true;
      } else {
        dbPath = initialDbPath;
        isDemo = false;
      }
      process.emit('jobhunt:db-switched', { isDemo });
      res.json({ ok: true, isDemo });
    } catch (err) {
      res.status(500).json({ error: String(err.message) });
    }
  });

  app.post('/api/db/reseed-demo', async (req, res) => {
    if (!isDemo || !demoDemoPath) return res.status(400).json({ error: 'Not in demo mode' });
    try {
      const { reseedDemoDb } = await import('./demo.js');
      reseedDemoDb(demoDemoPath);
      res.json({ ok: true });
    } catch (err) {
      res.status(500).json({ error: String(err.message) });
    }
  });

  // Ask the Electron window to come to front and navigate to a job.
  // No-op when running as a plain CLI server (process has no BrowserWindow).
  app.post('/api/app/focus', (req, res) => {
    const { job_number } = req.body || {};
    process.emit('jobhunt:open-job', { jobNumber: job_number ? Number(job_number) : null });
    res.json({ ok: true });
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
    res.json({ ...buildUiData(dbPath), isDemo });
  });

  app.get('/api/ui-data', (req, res) => {
    res.json({ ...buildUiData(dbPath), isDemo });
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
      if (result.created) {
        process.emit('jobhunt:job-added', {
          jobId: result.job_id,
          jobNumber: result.job_number,
          pageTitle: result.page_title || capture.page_title,
          duplicateOfJobId: result.duplicate_of_job_id,
        });
      }
      if (autoExtract && !result.duplicate) {
        runExtractionForApp(10).catch(() => {});
      }
      res.json({ ok: true, capture_id: result.capture_id, job_number: result.job_number, duplicate: result.duplicate });
    } catch (err) {
      res.status(400).json({ error: String(err.message) });
    }
  });

  // ------------------------------------------------------------------
  // Look up a job by URL (used by the extension's right-click menu)
  // ------------------------------------------------------------------

  app.get('/api/jobs/by-url', (req, res) => {
    const { url } = req.query;
    if (!url) return res.status(400).json({ error: 'url required' });
    const job = db.findJobByUrl(dbPath, url);
    if (!job) return res.status(404).json({ error: 'not found' });
    res.json(job);
  });

  // ------------------------------------------------------------------
  // Manual URL capture (server-side fetch)
  // ------------------------------------------------------------------

  app.post('/api/captures/from-url', async (req, res) => {
    const { url, note = '' } = req.body || {};
    if (!url) return res.status(400).json({ error: 'url required' });
    let safeUrl;
    try {
      safeUrl = validateFetchableCaptureUrl(url);
    } catch (err) {
      return res.status(400).json({ error: String(err.message) });
    }
    try {
      const response = await fetch(safeUrl, {
        headers: { 'User-Agent': 'Mozilla/5.0 (compatible; Jobhunt/1.0)' },
        signal: AbortSignal.timeout(15000),
        redirect: 'follow',
      });
      try {
        validateFetchableCaptureUrl(response.url);
      } catch (err) {
        return res.status(400).json({ error: String(err.message) });
      }
      if (!response.ok) return res.status(400).json({ error: `Fetch failed: HTTP ${response.status}` });
      const contentLength = Number(response.headers.get('content-length') || 0);
      if (contentLength > 10 * 1024 * 1024) return res.status(400).json({ error: 'Response too large (>10MB)' });
      const html = await response.text();
      if (html.length > 10 * 1024 * 1024) return res.status(400).json({ error: 'Response too large (>10MB)' });
      const titleMatch = html.match(/<title[^>]*>([^<]+)<\/title>/i);
      const pageTitle = titleMatch ? titleMatch[1].trim().replace(/\s+/g, ' ') : url;
      const visibleText = html
        .replace(/<script[\s\S]*?<\/script>/gi, ' ')
        .replace(/<style[\s\S]*?<\/style>/gi, ' ')
        .replace(/<[^>]+>/g, ' ')
        .replace(/&[a-z]+;/gi, ' ')
        .replace(/\s+/g, ' ')
        .trim()
        .slice(0, 50000);
      const capture = {
        schema_version: 1,
        captured_at: new Date().toISOString(),
        url: safeUrl,
        canonical_url: null,
        page_title: pageTitle,
        visible_text: visibleText,
        selected_text: '',
        structured_data: [],
        user_note: note,
        source: { extension_version: null, browser: 'manual' },
      };
      const result = db.insertCapture(capture, dbPath);
      if (result.created) {
        process.emit('jobhunt:job-added', {
          jobId: result.job_id,
          jobNumber: result.job_number,
          pageTitle: result.page_title || pageTitle,
          duplicateOfJobId: result.duplicate_of_job_id,
        });
      }
      if (autoExtract && !result.duplicate) runExtractionForApp(10).catch(() => {});
      res.json({ ok: true, capture_id: result.capture_id, duplicate: result.duplicate });
    } catch (err) {
      res.status(500).json({ error: String(err.message) });
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
        await refreshRotationPool(settings);
        const extractor = buildExtractor(settings);
        const scorer = buildScorer(settings);
        summary = await runExtractionForSelected({ dbPath, extractor, requestIds, scorer });
        emitAiRunComplete(summary);
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
      await refreshRotationPool(settings);
      const extractor = buildExtractor(settings);
      const scorer = buildScorer(settings);
      const summary = await runExtractionForSelected({
        dbPath,
        extractor,
        requestIds: [requestId],
        scorer,
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

  app.post('/api/jobs/bulk/llm', async (req, res) => {
    try {
      const result = db.queueBulkLlmJobs(req.body.job_ids, req.body.mode, dbPath);
      // Explicit user action: unpause queue and run the specific requests directly,
      // bypassing the queue-paused guard so nothing can block a manual trigger.
      const d = db.initDb(dbPath);
      db.setSetting(d, 'llm_queue_paused', 'false');
      if (result.request_ids?.length) {
        const settings = getDbSettings();
        await refreshRotationPool(settings);
        runExtractionForSelected({ dbPath, extractor: buildExtractor(settings), requestIds: result.request_ids, scorer: buildScorer(settings) }).then(emitAiRunComplete).catch(() => {});
      } else if (autoExtract) {
        runExtractionForApp(100).catch(() => {});
      }
      res.json({ ok: true, ...result });
    } catch (err) {
      res.status(400).json({ error: String(err.message) });
    }
  });

  app.post('/api/jobs/bulk/llm-by-number', async (req, res) => {
    try {
      const result = db.queueBulkLlmJobsByNumbers(req.body.job_numbers, req.body.mode, dbPath);
      const d = db.initDb(dbPath);
      db.setSetting(d, 'llm_queue_paused', 'false');
      if (result.request_ids?.length) {
        const settings = getDbSettings();
        await refreshRotationPool(settings);
        runExtractionForSelected({ dbPath, extractor: buildExtractor(settings), requestIds: result.request_ids, scorer: buildScorer(settings) }).then(emitAiRunComplete).catch(() => {});
      } else if (autoExtract) {
        runExtractionForApp(100).catch(() => {});
      }
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

  app.delete('/api/jobs/:jobId', (req, res) => {
    try {
      const deleted = db.deleteJob(req.params.jobId, dbPath);
      if (!deleted) return res.status(404).json({ error: 'Job not found' });
      res.json({ ok: true });
    } catch (err) {
      res.status(400).json({ error: String(err.message) });
    }
  });

  app.post('/api/jobs/:jobId/opened', (req, res) => {
    try {
      res.json({ ok: true, ...db.markJobOpened(req.params.jobId, dbPath) });
    } catch (err) {
      res.status(400).json({ error: String(err.message) });
    }
  });

  app.post('/api/jobs/:jobId/read', (req, res) => {
    try {
      db.markJobRead(req.params.jobId, dbPath);
      process.emit('jobhunt:job-read');
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
      const row = d.prepare("SELECT extraction_status FROM jobs WHERE id=?").get(req.params.jobId);
      if (!row) return res.status(400).json({ error: 'job not found' });
      if (row.extraction_status !== 'succeeded') {
        return res.status(400).json({ error: 'Extract this job before scoring fit.' });
      }
      const resumeId = req.body?.resume_id;
      if (resumeId) {
        db.queueFitScoreForJob(dbPath, req.params.jobId, String(resumeId), { resetAttempts: true });
      } else {
        if (!db.getActiveResumes(dbPath).length) {
          return res.status(400).json({ error: 'Add a resume in Settings before scoring fit.' });
        }
        db.queueFitScoresForAllResumes(dbPath, req.params.jobId, { resetAttempts: true });
      }
      if (autoExtract) runExtractionForApp(100).catch(() => {});
      res.json({ ok: true });
    } catch (err) {
      res.status(400).json({ error: String(err.message) });
    }
  });

  // ------------------------------------------------------------------
  // Resumes
  // ------------------------------------------------------------------

  app.get('/api/resumes', (req, res) => {
    res.json({ resumes: db.listResumes(dbPath) });
  });

  app.get('/api/resumes/:id', (req, res) => {
    const resume = db.getResume(dbPath, req.params.id);
    if (!resume) return res.status(404).json({ error: 'resume not found' });
    res.json(resume);
  });

  app.post('/api/resumes', (req, res) => {
    try {
      const text = String(req.body?.text || '');
      if (!text.trim()) {
        return res.status(400).json({ error: 'Resume text is empty. If this was a scanned/image PDF, paste the text manually.' });
      }
      const name = String(req.body?.name || '').trim() || 'Resume';
      const filename = req.body?.filename ? String(req.body.filename) : null;
      const resume = db.addResume(dbPath, { name, filename, text });
      // Backfill: score every already-extracted job against the new resume.
      const d = db.initDb(dbPath);
      const jobs = d.prepare("SELECT id FROM jobs WHERE extraction_status='succeeded'").all();
      for (const job of jobs) db.queueFitScoreForJob(dbPath, job.id, resume.id, { resetAttempts: true });
      if (autoExtract && jobs.length) runExtractionForApp(100).catch(() => {});
      res.json({ ok: true, resume, queued_jobs: jobs.length });
    } catch (err) {
      res.status(400).json({ error: String(err.message) });
    }
  });

  app.patch('/api/resumes/:id', (req, res) => {
    try {
      if (!db.getResume(dbPath, req.params.id)) return res.status(404).json({ error: 'resume not found' });
      if (req.body?.name != null) db.renameResume(dbPath, req.params.id, String(req.body.name));
      if (req.body?.text != null) db.updateResumeText(dbPath, req.params.id, String(req.body.text));
      if (req.body?.active != null) db.setResumeActive(dbPath, req.params.id, !!req.body.active);
      res.json({ ok: true, resume: db.getResume(dbPath, req.params.id) });
    } catch (err) {
      res.status(400).json({ error: String(err.message) });
    }
  });

  app.delete('/api/resumes/:id', (req, res) => {
    try {
      const affected = db.deleteResume(dbPath, req.params.id);
      res.json({ ok: true, recomputed_jobs: affected });
    } catch (err) {
      res.status(400).json({ error: String(err.message) });
    }
  });

  // ------------------------------------------------------------------
  // Cover letters
  // ------------------------------------------------------------------

  app.get('/api/jobs/:jobId/cover-letters', (req, res) => {
    try {
      const coverLetters = db.listCoverLetters(dbPath, req.params.jobId);
      res.json({ coverLetters });
    } catch (err) {
      res.status(500).json({ error: String(err.message) });
    }
  });

  app.post('/api/jobs/:jobId/generate-cover-letter', async (req, res) => {
    try {
      const d = db.initDb(dbPath);
      const job = d.prepare(`SELECT jobs.id, jobs.company, jobs.title, jobs.extracted_json,
        captures.cleaned_description
        FROM jobs JOIN captures ON captures.id=jobs.capture_id
        WHERE jobs.id=?`).get(req.params.jobId);
      if (!job) return res.status(404).json({ error: 'job not found' });

      const { resumeId, instructions } = req.body || {};
      let resume = null;
      if (resumeId) {
        resume = db.getResume(dbPath, resumeId);
        if (!resume) return res.status(400).json({ error: 'resume not found' });
      } else {
        const active = db.getActiveResumes(dbPath);
        if (!active.length) return res.status(400).json({ error: 'No resume available. Add a resume in Settings.' });
        resume = active[0];
      }

      if (!String(resume.text || '').trim()) {
        return res.status(400).json({ error: 'Resume has no text.' });
      }

      const settings = getDbSettings();
      let result;
      try {
        result = await generateCoverLetter({
          job,
          resumeText: resume.text,
          instructions: instructions || '',
          settings,
        });
      } catch (err) {
        return res.status(500).json({ error: `LLM error: ${String(err.message)}` });
      }

      const saved = db.saveCoverLetter(dbPath, {
        jobId: req.params.jobId,
        resumeId: resume.id,
        content: result.content,
        instructions: instructions || null,
        model: result.modelName || null,
      });

      res.json({ coverLetter: saved });
    } catch (err) {
      res.status(500).json({ error: String(err.message) });
    }
  });

  app.delete('/api/cover-letters/:coverId', (req, res) => {
    try {
      const result = db.deleteCoverLetter(dbPath, req.params.coverId);
      if (!result.deleted) return res.status(404).json({ error: 'cover letter not found' });
      res.json({ ok: true });
    } catch (err) {
      res.status(500).json({ error: String(err.message) });
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
      if (cleaned_hash) {
        db.decideDuplicateGroup(cleaned_hash, decision, keep_job_id, note || '', dbPath);
      } else {
        db.decideDuplicateLinks(req.body.job_ids, decision, keep_job_id, note || '', dbPath);
      }
      res.json({ ok: true });
    } catch (err) {
      res.status(400).json({ error: String(err.message) });
    }
  });

  // ------------------------------------------------------------------
  // Debug
  // ------------------------------------------------------------------

  app.get('/api/debug/stats', (req, res) => {
    try {
      const d = db.initDb(dbPath);
      const jobsByStatus = d.prepare(`SELECT status, COUNT(*) as n FROM jobs GROUP BY status`).all();
      const jobsByExtraction = d.prepare(`SELECT extraction_status, COUNT(*) as n FROM jobs GROUP BY extraction_status`).all();
      const llmCounts = d.prepare(`SELECT status, COUNT(*) as n FROM llm_requests GROUP BY status`).all();
      const captureCount = d.prepare(`SELECT COUNT(*) as n FROM captures`).get().n;
      const resolvedPath = resolve(dbPath || db.defaultDbPath());
      const dbSize = (() => { try { return statSync(resolvedPath).size; } catch { return null; } })();
      const promptStats = d.prepare(`
        SELECT COUNT(*) as attempts,
          MAX(prompt_chars) as max_prompt_chars,
          CAST(ROUND(AVG(prompt_chars)) AS INT) as avg_prompt_chars,
          CAST(ROUND(AVG(duration_ms)) AS INT) as avg_duration_ms,
          MAX(duration_ms) as max_duration_ms
        FROM llm_request_attempts WHERE status='succeeded' AND prompt_chars IS NOT NULL`).get();
      const jdStats = d.prepare(`
        SELECT MAX(LENGTH(cleaned_description)) as max_jd_chars,
          CAST(ROUND(AVG(LENGTH(cleaned_description))) AS INT) as avg_jd_chars
        FROM captures WHERE cleaned_description IS NOT NULL AND LENGTH(TRIM(cleaned_description)) > 100`).get();
      res.json({
        jobsByStatus, jobsByExtraction, llmCounts, captureCount, dbSize, dbPath: resolvedPath,
        promptStats, jdStats,
        tokenCaps: { maxDescriptionChars: MAX_DESCRIPTION_CHARS, maxResumeChars: MAX_RESUME_CHARS },
      });
    } catch (err) {
      res.status(500).json({ error: String(err.message) });
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

  const VALID_CONSENT_PROVIDERS = ['anthropic', 'google', 'openrouter', 'openai'];

  app.get('/api/settings/llm-consent/:provider', (req, res) => {
    try {
      const { provider } = req.params;
      if (!VALID_CONSENT_PROVIDERS.includes(provider)) return res.status(400).json({ error: 'invalid provider' });
      const d = db.initDb(dbPath);
      const val = d.prepare('SELECT value FROM settings WHERE key = ?').get(`llm_consent_${provider}`);
      res.json({ provider, consented: val?.value === '1' });
    } catch (e) {
      res.status(500).json({ error: e.message });
    }
  });

  app.post('/api/settings/llm-consent/:provider', (req, res) => {
    try {
      const { provider } = req.params;
      if (!VALID_CONSENT_PROVIDERS.includes(provider)) return res.status(400).json({ error: 'invalid provider' });
      const { consented } = req.body;
      const d = db.initDb(dbPath);
      db.setSetting(d, `llm_consent_${provider}`, consented ? '1' : '0');
      res.json({ ok: true });
    } catch (e) {
      res.status(500).json({ error: e.message });
    }
  });

  app.post('/api/settings/test-llm', async (req, res) => {
    try {
      const settings = getDbSettings();
      const provider = req.body?.provider || settings.llm_provider || 'lmstudio';
      const apiKey = req.body?.api_key || resolveApiKey({ ...settings, llm_provider: provider });
      const model = req.body?.model || settings.llm_model || '';
      const rawBaseUrl = req.body?.base_url || settings.llm_base_url || 'http://127.0.0.1:1234';

      if (provider === 'anthropic') {
        if (!apiKey) return res.json({ ok: true, models: [] });
        const ac = new AbortController();
        const at = setTimeout(() => ac.abort(), 6000);
        try {
          const ar = await fetch('https://api.anthropic.com/v1/models?limit=100', {
            headers: { 'x-api-key': apiKey, 'anthropic-version': '2023-06-01' },
            signal: ac.signal,
          });
          if (!ar.ok) return res.json({ ok: false, error: `HTTP ${ar.status}` });
          const ad = await ar.json();
          const models = (ad.data || []).map(m => m.id || '').filter(Boolean);
          if (req.body?.quick) return res.json({ ok: true, models });
          return res.json({ ok: true, models, modelTests: [{ name: 'Provider', status: 'pass', message: 'Anthropic — uses native Messages API' }] });
        } catch (e) {
          return res.json({ ok: false, error: e.name === 'AbortError' ? 'Connection timed out' : String(e.message) });
        } finally { clearTimeout(at); }
      }
      if (provider === 'google') {
        if (!apiKey) return res.json({ ok: true, models: [] });
        const gc = new AbortController();
        const gt = setTimeout(() => gc.abort(), 6000);
        try {
          const gr = await fetch(`https://generativelanguage.googleapis.com/v1beta/models?key=${apiKey}&pageSize=100`, { signal: gc.signal });
          if (!gr.ok) return res.json({ ok: false, error: `HTTP ${gr.status}` });
          const gd = await gr.json();
          const models = (gd.models || [])
            .filter(m => (m.supportedGenerationMethods || []).includes('generateContent'))
            .map(m => (m.name || '').replace(/^models\//, ''))
            .filter(id => id.startsWith('gemini'));
          if (req.body?.quick) return res.json({ ok: true, models });
          return res.json({ ok: true, models, modelTests: [{ name: 'Provider', status: 'pass', message: 'Google Gemini — uses native generateContent API' }] });
        } catch (e) {
          return res.json({ ok: false, error: e.name === 'AbortError' ? 'Connection timed out' : String(e.message) });
        } finally { clearTimeout(gt); }
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
        if (!response.ok) {
          return res.json({ ok: false, error: `HTTP ${response.status}` });
        } else {
          const data = /** @type {any} */ (await response.json());
          const allIds = (data.data || []).map(m => m.id || '').filter(Boolean);
          // For OpenAI, drop embeddings/audio/image/legacy models — keep only chat/reasoning models
          modelIds = provider === 'openai'
            ? allIds.filter(id => /^(gpt-|o[0-9])/.test(id) && !id.includes('instruct') && !id.includes('realtime') && !id.includes('audio') && !id.includes('tts') && !id.includes('whisper') && !id.includes('search'))
            : allIds;
        }
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

  // Returns the filtered list of free OpenRouter models that support structured output.
  app.get('/api/settings/free-models', async (req, res) => {
    try {
      const s = getDbSettings();
      const apiKey = resolveApiKey({ ...s, llm_provider: 'openrouter' });
      const models = await fetchFreeModelIds(apiKey);
      res.json({ ok: true, models });
    } catch (e) {
      res.json({ ok: false, error: e.name === 'AbortError' ? 'Connection timed out' : String(e.message) });
    }
  });

  // Known context windows for hardcoded provider models (tokens)
  const KNOWN_CONTEXT_LENGTHS = {
    'gpt-4o': 128000, 'gpt-4o-mini': 128000,
    'o3': 200000, 'o3-mini': 200000,
    'claude-opus-4-8': 200000, 'claude-sonnet-4-6': 200000, 'claude-haiku-4-5-20251001': 200000,
    'gemini-2.5-pro': 1048576, 'gemini-2.5-flash': 1048576, 'gemini-2.0-flash': 1048576,
    'gemini-1.5-pro': 2000000, 'gemini-1.5-flash': 1000000,
  };

  // Minimum recommended context (tokens): max description + resume + system prompt overhead
  const RECOMMENDED_MIN_TOKENS = Math.ceil((MAX_DESCRIPTION_CHARS + MAX_RESUME_CHARS) / 4) + 2000;

  app.get('/api/settings/model-context', async (req, res) => {
    try {
      const settings = getDbSettings();
      const provider = settings.llm_provider || 'lmstudio';
      const apiKey = resolveApiKey(settings);
      const model = settings.llm_model || '';
      const rawBaseUrl = settings.llm_base_url || 'http://127.0.0.1:1234';

      const maxObservedChars = db.getMaxObservedPromptChars(dbPath);
      const maxObservedPromptTokens = maxObservedChars ? Math.ceil(maxObservedChars / 4) : null;

      // Try to resolve context length from provider
      let contextLength = KNOWN_CONTEXT_LENGTHS[model] || null;

      // For OpenRouter, query model info endpoint for exact context length
      if (!contextLength && provider === 'openrouter' && model) {
        try {
          const headers = {};
          if (apiKey) headers['Authorization'] = `Bearer ${apiKey}`;
          const controller = new AbortController();
          const timer = setTimeout(() => controller.abort(), 5000);
          try {
            const r = await fetch(`https://openrouter.ai/api/v1/models`, { headers, signal: controller.signal });
            if (r.ok) {
              const data = await r.json();
              const found = (data.data || []).find(m => m.id === model);
              if (found?.context_length) contextLength = found.context_length;
            }
          } finally {
            clearTimeout(timer);
          }
        } catch { /* ignore */ }
      }

      // For LM Studio: try /api/v0/models first (richer, includes loaded_context_length)
      if (!contextLength && provider === 'lmstudio') {
        try {
          const baseUrl = resolveProviderBaseUrl(provider, rawBaseUrl);
          const controller = new AbortController();
          const timer = setTimeout(() => controller.abort(), 5000);
          try {
            const r = await fetch(`${baseUrl}/api/v0/models`, { signal: controller.signal });
            if (r.ok) {
              const data = await r.json();
              const models = data.data || [];
              // Prefer exact match, fall back to the only loaded model
              const exact = models.find(m => m.id === model);
              const loaded = models.find(m => m.state === 'loaded');
              const best = exact || loaded;
              if (best?.loaded_context_length) contextLength = best.loaded_context_length;
              else if (best?.max_context_length) contextLength = best.max_context_length;
            }
          } finally {
            clearTimeout(timer);
          }
        } catch { /* ignore */ }
      }

      // For custom OpenAI-compatible: /v1/models may return max_context_length
      if (!contextLength && provider === 'custom' && model) {
        try {
          const baseUrl = resolveProviderBaseUrl(provider, rawBaseUrl);
          const controller = new AbortController();
          const timer = setTimeout(() => controller.abort(), 5000);
          try {
            const r = await fetch(`${baseUrl}/v1/models`, { signal: controller.signal });
            if (r.ok) {
              const data = await r.json();
              const models = data.data || [];
              const found = models.find(m => m.id === model) || models[0];
              if (found?.max_context_length) contextLength = found.max_context_length;
            }
          } finally {
            clearTimeout(timer);
          }
        } catch { /* ignore */ }
      }

      res.json({
        contextLength,
        maxObservedPromptTokens,
        recommendedMinTokens: RECOMMENDED_MIN_TOKENS,
      });
    } catch (err) {
      res.status(500).json({ error: String(err.message) });
    }
  });

  // Estimated input/output token totals to process all jobs (extraction + fit
  // scoring against active resumes). Cost is applied client-side from prices.
  app.get('/api/llm-cost', (req, res) => {
    try {
      const d = db.initDb(dbPath);
      const settings = db.getSettings(d);
      const CPT = 4;
      const { extractChars, fitChars } = promptOverheadChars({
        preferredLocations: settings.preferred_locations,
        allowRemote: settings.location_allow_remote !== 'false',
        allowHybrid: settings.location_allow_hybrid !== 'false',
        allowOnsite: settings.location_allow_onsite !== 'false',
      });

      const jobRows = d.prepare(`
        SELECT jobs.extraction_status AS status,
          LENGTH(COALESCE(NULLIF(captures.cleaned_description,''), NULLIF(captures.selected_text,''), captures.visible_text)) AS jd_chars,
          LENGTH(jobs.extracted_json) AS extracted_chars
        FROM jobs JOIN captures ON captures.id = jobs.capture_id`).all();
      const jobsTotal = jobRows.length;
      const resumes = d.prepare("SELECT char_count FROM resumes WHERE active=1").all();
      const resumesActive = resumes.length;

      // Output-size proxies from real stored data, with fallbacks when empty.
      const avgExtractedChars = Math.round(d.prepare("SELECT AVG(LENGTH(extracted_json)) AS a FROM jobs WHERE extraction_status='succeeded' AND extracted_json IS NOT NULL").get().a || 1200);
      const avgFitOutputChars = Math.round(d.prepare("SELECT AVG(LENGTH(fit_score_json)) AS a FROM job_fit_scores WHERE fit_status='succeeded' AND fit_score_json IS NOT NULL").get().a || 900);
      const doneFitPairs = d.prepare("SELECT COUNT(*) AS c FROM job_fit_scores WHERE fit_status='succeeded'").get().c;

      const clamp = (n, max) => Math.min(n || 0, max);
      let allExtIn = 0, allExtOut = 0, remExtIn = 0, remExtOut = 0, jdCharsSum = 0;
      for (const j of jobRows) {
        const inChars = extractChars + clamp(j.jd_chars, MAX_DESCRIPTION_CHARS);
        allExtIn += inChars / CPT;
        allExtOut += (j.extracted_chars || avgExtractedChars) / CPT;
        jdCharsSum += (j.jd_chars || 0);
        if (j.status !== 'succeeded') {
          remExtIn += inChars / CPT;
          remExtOut += avgExtractedChars / CPT; // not yet extracted → use avg output size
        }
      }

      let allFitIn = 0, allFitOut = 0, resumeCharsSum = 0;
      for (const r of resumes) resumeCharsSum += (r.char_count || 0);
      for (const j of jobRows) {
        const fields = j.extracted_chars || avgExtractedChars;
        for (const r of resumes) {
          allFitIn += (fitChars + fields + clamp(r.char_count, MAX_RESUME_CHARS)) / CPT;
          allFitOut += avgFitOutputChars / CPT;
        }
      }
      const fitPairsTotal = jobsTotal * resumesActive;
      const remFitPairs = Math.max(0, fitPairsTotal - doneFitPairs);
      const remFitIn = fitPairsTotal ? (allFitIn / fitPairsTotal) * remFitPairs : 0;
      const remFitOut = fitPairsTotal ? (allFitOut / fitPairsTotal) * remFitPairs : 0;

      const r0 = Math.round;
      const perJob = (n) => (jobsTotal ? r0(n / jobsTotal) : 0);
      res.json({
        has_data: jobsTotal > 0,
        jobs_total: jobsTotal,
        jobs_extracted: jobRows.filter(j => j.status === 'succeeded').length,
        resumes_active: resumesActive,
        fit_pairs_total: fitPairsTotal,
        fit_pairs_done: doneFitPairs,
        chars_per_token: CPT,
        avg_jd_chars: jobsTotal ? Math.round(jdCharsSum / jobsTotal) : 0,
        avg_resume_chars: resumesActive ? Math.round(resumeCharsSum / resumesActive) : 0,
        all: {
          extraction: { input_tokens: r0(allExtIn), output_tokens: r0(allExtOut) },
          fit: { input_tokens: r0(allFitIn), output_tokens: r0(allFitOut) },
        },
        remaining: {
          extraction: { input_tokens: r0(remExtIn), output_tokens: r0(remExtOut) },
          fit: { input_tokens: r0(remFitIn), output_tokens: r0(remFitOut) },
        },
        per_job: {
          extraction: { input_tokens: perJob(allExtIn), output_tokens: perJob(allExtOut) },
          fit: { input_tokens: perJob(allFitIn), output_tokens: perJob(allFitOut) },
        },
      });
    } catch (err) {
      res.status(500).json({ error: String(err.message) });
    }
  });

  // Live model prices from OpenRouter (USD per 1M tokens). Proxied to avoid
  // browser CORS; degrades to an empty list so the UI falls back to manual entry.
  app.get('/api/llm-pricing', async (req, res) => {
    try {
      const controller = new AbortController();
      const timer = setTimeout(() => controller.abort(), 6000);
      let data;
      try {
        const r = await fetch('https://openrouter.ai/api/v1/models', { signal: controller.signal });
        if (!r.ok) throw new Error(`OpenRouter HTTP ${r.status}`);
        data = /** @type {any} */ (await r.json());
      } finally {
        clearTimeout(timer);
      }
      const models = (data.data || [])
        .map(m => {
          const inP = Number(m.pricing?.prompt);
          const outP = Number(m.pricing?.completion);
          if (!Number.isFinite(inP) || !Number.isFinite(outP)) return null;
          return { id: m.id, name: m.name || m.id, input_per_1m: +(inP * 1e6).toFixed(4), output_per_1m: +(outP * 1e6).toFixed(4) };
        })
        .filter(Boolean)
        .sort((a, b) => a.id.localeCompare(b.id));
      res.json({ models });
    } catch (err) {
      res.json({ models: [], error: String(err.message) });
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
  db.detectDomainDuplicateJobs(dbPath);
  const settingsData = db.getSettings(d);

  const jobRows = d.prepare(`SELECT jobs.id AS job_id, jobs.job_number, jobs.capture_id,
    jobs.status, jobs.extraction_status, jobs.extraction_error, jobs.company, jobs.title,
    jobs.location, jobs.remote_type, jobs.salary_min, jobs.salary_max, jobs.salary_currency,
    jobs.salary_note, jobs.extracted_json, jobs.extracted_at, jobs.fit_score, jobs.fit_status,
    jobs.fit_score_json, jobs.rating, jobs.duplicate_of_job_id, jobs.extraction_model,
    jobs.application_url, jobs.extraction_confidence, jobs.manual_overrides,
    jobs.last_opened_at, jobs.unread,
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

  const fitScoresByJob = Object.fromEntries(jobIds.map(id => [id, []]));
  if (jobIds.length) {
    const placeholders = jobIds.map(() => '?').join(',');
    const fitRows = d.prepare(`SELECT jfs.job_id, jfs.resume_id, r.name AS resume_name, r.active AS resume_active,
      jfs.fit_score, jfs.fit_status, jfs.fit_score_json, jfs.model, jfs.scored_at
      FROM job_fit_scores jfs JOIN resumes r ON r.id = jfs.resume_id
      WHERE jfs.job_id IN (${placeholders})
      ORDER BY r.sort_order, r.created_at`).all(...jobIds);
    for (const fr of fitRows) {
      if (!fitScoresByJob[fr.job_id]) continue;
      let json = fr.fit_score_json;
      if (json && typeof json === 'string') {
        try { json = JSON.parse(json); } catch { json = null; }
      }
      fitScoresByJob[fr.job_id].push({
        resume_id: fr.resume_id,
        resume_name: fr.resume_name,
        resume_active: fr.resume_active ? 1 : 0,
        score: fr.fit_score,
        status: fr.fit_status,
        summary: json?.summary || null,
        requirements_met: json?.requirements_met || [],
        requirements_not_met: json?.requirements_not_met || [],
        dimensions: json?.dimensions || [],
        model: json?.model || fr.model || null,
        scored_at: json?.scored_at || fr.scored_at || null,
        error: json?.error || null,
      });
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
      SELECT captures.cleaned_hash
      FROM captures JOIN jobs ON jobs.capture_id=captures.id
      WHERE captures.cleaned_hash IS NOT NULL
        AND LENGTH(TRIM(COALESCE(captures.cleaned_description, ''))) >= 200
        AND jobs.status NOT IN ('archived', 'not_available', 'duplicate')
      GROUP BY cleaned_hash HAVING COUNT(DISTINCT COALESCE(canonical_url, url)) > 1
    ) AND duplicate_decisions.cleaned_hash IS NULL
      AND LENGTH(TRIM(COALESCE(captures.cleaned_description, ''))) >= 200
      AND jobs.status NOT IN ('archived', 'not_available', 'duplicate')
    ORDER BY captures.cleaned_hash`).all();

  const dupGroups = {};
  for (const row of dupRows) {
    if (!dupGroups[row.cleaned_hash]) dupGroups[row.cleaned_hash] = [];
    dupGroups[row.cleaned_hash].push(row.job_id);
  }
  const dupes = Object.entries(dupGroups).map(([h, ids], i) => ({
    group_id: `g-${i}`,
    kind: 'exact_hash',
    cleaned_hash: h,
    job_ids: ids,
    reason: 'Identical cleaned description hash',
    similarity: 1.0,
  }));

  const heuristicRows = d.prepare(`SELECT duplicate_of_job_id AS keep_job_id,
      GROUP_CONCAT(id) AS duplicate_job_ids,
      MAX(COALESCE(duplicate_confidence, 0)) AS confidence
    FROM jobs
    WHERE duplicate_of_job_id IS NOT NULL AND status NOT IN ('duplicate', 'archived', 'not_available')
    GROUP BY duplicate_of_job_id
    ORDER BY MAX(updated_at) DESC`).all();
  heuristicRows.forEach((row, i) => {
    const duplicateIds = String(row.duplicate_job_ids || '').split(',').filter(Boolean);
    if (!row.keep_job_id || duplicateIds.length === 0) return;
    dupes.push({
      group_id: `h-${i}-${row.keep_job_id}`,
      kind: 'domain_candidate',
      cleaned_hash: '',
      job_ids: [row.keep_job_id, ...duplicateIds],
      reason: 'Likely duplicate: matching company, title, description, and critical fields',
      similarity: Number(row.confidence || 0),
    });
  });

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
      fit_scores: fitScoresByJob[r.job_id] || [],
      rating: r.rating, duplicate_of_job_id: r.duplicate_of_job_id,
      extraction_model: r.extraction_model, application_url: r.application_url,
      extraction_confidence: r.extraction_confidence, cleaned_description: r.cleaned_description,
      manual_overrides: r.manual_overrides, last_opened_at: r.last_opened_at, unread: r.unread ? 1 : 0,
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
    jobs, sites: siteRows, dupes, metrics, metros: METRO_DATA,
    resumes: db.listResumes(dbPath),
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
      llm_api_key_openai: settingsData.llm_api_key_openai || '',
      llm_api_key_anthropic: settingsData.llm_api_key_anthropic || '',
      llm_api_key_google: settingsData.llm_api_key_google || '',
      llm_api_key_openrouter: settingsData.llm_api_key_openrouter || '',
      llm_api_key_custom: settingsData.llm_api_key_custom || '',
      llm_model: settingsData.llm_model,
      site_review_interval_days: parseInt(settingsData.site_review_interval_days || '14'),
      followup_default_days: parseInt(settingsData.followup_default_days || '7'),
      job_description_markdown: settingsData.job_description_markdown || '',
      llm_price_input: settingsData.llm_price_input || '0',
      llm_price_output: settingsData.llm_price_output || '0',
      llm_openrouter_free_rotate: settingsData.llm_openrouter_free_rotate || 'false',
      llm_queue_paused: settingsData.llm_queue_paused || 'false',
      llm_debug_level: settingsData.llm_debug_level || 'errors',
      preferred_locations: settingsData.preferred_locations || '',
      location_allow_remote: settingsData.location_allow_remote || 'true',
      location_allow_hybrid: settingsData.location_allow_hybrid || 'true',
      location_allow_onsite: settingsData.location_allow_onsite || 'true',
      preferred_metros: settingsData.preferred_metros || '',
      location_filter_enabled: settingsData.location_filter_enabled || 'true',
    },
  };
}

export const DB_STATUS_TO_UI = { interested: 'saved', interviewing: 'interview', closed: 'archived', ignored: 'archived' };

export function buildMetrics(jobs, sites, dupes, needsActionCount) {
  const counts = { saved: 0, applied: 0, interview: 0, offers: 0, rejected: 0, archived: 0, duplicates: 0, pendingExtraction: 0, failedExtraction: 0 };
  for (const job of jobs) {
    const status = DB_STATUS_TO_UI[job.status] || job.status;
    if (status === 'saved') counts.saved++;
    else if (status === 'applied') counts.applied++;
    else if (status === 'interview') counts.interview++;
    else if (status === 'offer') counts.offers++;
    else if (status === 'rejected') counts.rejected++;
    else if (status === 'archived') counts.archived++;
    else if (status === 'duplicate') counts.duplicates++;
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
