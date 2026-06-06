// Mirrors python/src/jobhunt/availability.py

import { getSettings, initDb, setSetting, updateJobStatus } from './db.js';

const USER_AGENT = 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36';
const GONE_STATUS_CODES = new Set([404, 410]);
const GONE_BODY_PATTERNS = [
  'page not found', 'job not found', 'job no longer available',
  'this job is no longer', 'position is no longer available', 'position has been filled',
  'posting has expired', 'job posting has expired', 'no longer accepting applications',
  'job listing has expired', 'this position has been filled', 'this role is no longer',
  'opening is no longer', 'requisition is no longer', 'job has been closed',
  'this job has been removed',
];

export function _normalizeUrlForCompare(url) { return normalizeUrlForCompare(url); }
function normalizeUrlForCompare(url) {
  try {
    const parsed = new URL(url);
    parsed.hash = '';
    parsed.searchParams.sort();
    parsed.pathname = parsed.pathname.replace(/\/+$/, '') || '/';
    return parsed.toString();
  } catch (_e) {
    return String(url || '').replace(/\/+$/, '');
  }
}

function normalizeText(value) {
  return String(value || '').toLowerCase().replace(/[^a-z0-9]+/g, ' ').trim();
}

function isMeaningfulTitle(title) {
  return normalizeText(title).split(' ').filter(Boolean).length >= 3;
}

function bodyContainsTitle(body, title) {
  if (!isMeaningfulTitle(title)) return true;
  return normalizeText(body).includes(normalizeText(title));
}

function redirectedToNonJobPage(originalUrl, finalUrl) {
  if (normalizeUrlForCompare(originalUrl) === normalizeUrlForCompare(finalUrl)) return false;
  try {
    const original = new URL(originalUrl);
    const final = new URL(finalUrl);
    const path = final.pathname.toLowerCase().replace(/\/+$/, '') || '/';
    const originalPath = original.pathname.toLowerCase().replace(/\/+$/, '') || '/';
    if (original.hostname !== final.hostname) return false;
    if (path === '/' || path === '/jobs' || path === '/careers') return true;
    if (/\/compan(y|ies)\//.test(path)) return true;
    if (path !== originalPath && /\/(search|jobs|careers|openings)$/.test(path)) return true;
  } catch (_e) {
    return false;
  }
  return false;
}

export async function checkUrl(job, fetchImpl = fetch) {
  const { id: jobId, url, title } = job;
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), 12000);
  try {
    const res = await fetchImpl(url, {
      headers: { 'User-Agent': USER_AGENT },
      signal: controller.signal,
      redirect: 'follow',
    });
    const finalUrl = res.url || url;
    if (GONE_STATUS_CODES.has(res.status)) {
      return { jobId, url, available: false, reason: `HTTP ${res.status}` };
    }
    const body = (await res.text()).toLowerCase();
    for (const pattern of GONE_BODY_PATTERNS) {
      if (body.includes(pattern)) {
        return { jobId, url, available: false, reason: `body: ${pattern}` };
      }
    }
    if (redirectedToNonJobPage(url, finalUrl)) {
      return { jobId, url, available: false, reason: `redirected to non-job page: ${finalUrl}` };
    }
    if (normalizeUrlForCompare(url) !== normalizeUrlForCompare(finalUrl) && !bodyContainsTitle(body, title)) {
      return { jobId, url, available: false, reason: `redirected page missing title: ${finalUrl}` };
    }
    return { jobId, url, available: true, reason: 'ok' };
  } catch (e) {
    if (e.name === 'AbortError') return { jobId, url, available: true, reason: 'timeout' };
    return { jobId, url, available: true, reason: `error: ${e.message}` };
  } finally {
    clearTimeout(timer);
  }
}

export async function checkJobsAvailability(dbPath) {
  const db = initDb(dbPath);
  const rows = db.prepare(`SELECT j.id, j.job_number, j.title, c.url, c.canonical_url FROM jobs j
    JOIN captures c ON c.id=j.capture_id
    WHERE j.status NOT IN ('archived','not_available')
    AND (c.canonical_url IS NOT NULL OR c.url IS NOT NULL)`).all();

  const jobMeta = new Map(rows.map(r => [r.id, { jobNumber: r.job_number, title: r.title }]));
  const jobs = rows.map(r => ({ id: r.id, title: r.title, url: r.url || r.canonical_url }));
  if (!jobs.length) return { checked: 0, unavailable: 0, marked: 0 };

  const results = await Promise.all(jobs.map(j => checkUrl(j)));
  const unavailable = results.filter(r => !r.available);
  let marked = 0;
  for (const r of unavailable) {
    try {
      updateJobStatus(r.jobId, 'not_available', dbPath);
      marked++;
      const meta = jobMeta.get(r.jobId);
      process.emit('jobhunt:job-unavailable', { jobNumber: meta?.jobNumber, title: meta?.title });
    } catch { /* skip */ }
  }
  return { checked: results.length, unavailable: unavailable.length, marked };
}

export async function checkStaleJobsAvailability(dbPath, { staleDays = 21, limit = 25 } = {}) {
  const db = initDb(dbPath);
  const cutoff = new Date(Date.now() - Number(staleDays || 21) * 86400000).toISOString();
  const rows = db.prepare(`SELECT j.id, j.job_number, j.title, c.url, c.canonical_url, c.captured_at FROM jobs j
    JOIN captures c ON c.id=j.capture_id
    WHERE j.status NOT IN ('archived','not_available')
    AND (c.canonical_url IS NOT NULL OR c.url IS NOT NULL)
    AND c.captured_at <= ?
    ORDER BY c.captured_at ASC
    LIMIT ?`).all(cutoff, Number(limit || 25));

  const jobMeta = new Map(rows.map(r => [r.id, { jobNumber: r.job_number, title: r.title }]));
  const jobs = rows.map(r => ({ id: r.id, title: r.title, url: r.url || r.canonical_url }));
  if (!jobs.length) return { checked: 0, unavailable: 0, marked: 0 };

  const results = await Promise.all(jobs.map(j => checkUrl(j)));
  const unavailable = results.filter(r => !r.available);
  let marked = 0;
  for (const r of unavailable) {
    try {
      updateJobStatus(r.jobId, 'not_available', dbPath);
      marked++;
      const meta = jobMeta.get(r.jobId);
      process.emit('jobhunt:job-unavailable', { jobNumber: meta?.jobNumber, title: meta?.title });
    } catch { /* skip */ }
  }
  return { checked: results.length, unavailable: unavailable.length, marked };
}

export async function maybeRunStaleAvailabilityCheck(dbPath) {
  const db = initDb(dbPath);
  const settings = getSettings(db);
  if (String(settings.availability_auto_check_enabled).toLowerCase() !== 'true') {
    return { skipped: true, reason: 'disabled' };
  }
  const intervalDays = Math.max(1, Number(settings.availability_auto_check_interval_days || 1));
  const last = settings.availability_last_auto_check_at ? Date.parse(settings.availability_last_auto_check_at) : 0;
  if (last && Date.now() - last < intervalDays * 86400000) {
    return { skipped: true, reason: 'interval' };
  }
  const staleDays = Math.max(1, Number(settings.availability_stale_days || 21));
  const result = await checkStaleJobsAvailability(dbPath, { staleDays, limit: 25 });
  setSetting(db, 'availability_last_auto_check_at', new Date().toISOString());
  return { skipped: false, ...result };
}
