// Mirrors python/src/jobhunt/db.py
// Uses node:sqlite (built-in to Node 26+, synchronous) for all DB access.

import { DatabaseSync } from 'node:sqlite';
import { createHash } from 'crypto';
import { randomBytes } from 'crypto';
import { appendFileSync, copyFileSync, existsSync, mkdirSync } from 'fs';
import { homedir } from 'os';
import { dirname, join, resolve } from 'path';
import { cleanDescription } from './cleaning.js';

export const JOB_STATUSES = new Set([
  'saved', 'applied', 'interview', 'offer', 'rejected', 'archived', 'not_available', 'duplicate',
]);

export const ACTIVE_JOB_STATUSES = new Set(['saved', 'applied', 'interview', 'offer']);

const LEGACY_STATUS_MAP = {
  interested: 'saved',
  interviewing: 'interview',
  closed: 'archived',
  ignored: 'archived',
};

export const SITE_STATES = new Set(['not_reviewed', 'reviewed', 'exclude']);

export const SETTINGS_DEFAULTS = {
  llm_provider: 'lmstudio',
  llm_base_url: 'http://127.0.0.1:1234',
  llm_api_key: '',
  llm_model: 'gemma-4-e4b-it-mlx',
  llm_timeout: '300',
  site_review_interval_days: '14',
  followup_default_days: '7',
  job_description_markdown: '',
  preferred_locations: '',
  location_allow_remote: 'true',
  location_allow_hybrid: 'true',
  location_allow_onsite: 'true',
  llm_queue_paused: 'false',
  llm_debug_level: 'errors',
  availability_auto_check_enabled: 'true',
  availability_auto_check_interval_days: '1',
  availability_stale_days: '21',
  availability_last_auto_check_at: '',
  resume_text: '',
};

const SCHEMA = `
PRAGMA foreign_keys = ON;

CREATE TABLE IF NOT EXISTS captures (
  id TEXT PRIMARY KEY,
  url TEXT NOT NULL,
  canonical_url TEXT,
  page_title TEXT NOT NULL,
  selected_text TEXT,
  visible_text TEXT,
  cleaned_description TEXT,
  structured_data_json TEXT,
  user_note TEXT,
  raw_hash TEXT NOT NULL,
  cleaned_hash TEXT,
  captured_at TEXT NOT NULL,
  created_at TEXT NOT NULL,
  UNIQUE(raw_hash)
);

CREATE TABLE IF NOT EXISTS jobs (
  id TEXT PRIMARY KEY,
  job_number INTEGER UNIQUE,
  capture_id TEXT NOT NULL REFERENCES captures(id),
  company TEXT,
  title TEXT,
  location TEXT,
  remote_type TEXT,
  salary_min INTEGER,
  salary_max INTEGER,
  salary_currency TEXT,
  salary_note TEXT,
  employment_type TEXT,
  seniority TEXT,
  status TEXT NOT NULL DEFAULT 'saved',
  manual_overrides TEXT NOT NULL DEFAULT '[]',
  extracted_json TEXT,
  extraction_status TEXT NOT NULL DEFAULT 'pending',
  extraction_error TEXT,
  fit_score INTEGER,
  fit_status TEXT NOT NULL DEFAULT 'none',
  fit_score_json TEXT,
  duplicate_of_job_id TEXT REFERENCES jobs(id),
  duplicate_confidence REAL,
  extracted_at TEXT,
  rating INTEGER CHECK(rating BETWEEN 1 AND 5),
  extraction_model TEXT,
  application_url TEXT,
  extraction_confidence REAL,
  last_opened_at TEXT,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS events (
  id TEXT PRIMARY KEY,
  job_id TEXT NOT NULL REFERENCES jobs(id),
  event_type TEXT NOT NULL,
  note TEXT,
  occurred_at TEXT NOT NULL,
  created_at TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS site_reviews (
  id TEXT PRIMARY KEY,
  site_url TEXT NOT NULL,
  site_origin TEXT NOT NULL,
  page_title TEXT,
  reviewed_at TEXT NOT NULL,
  next_review_at TEXT,
  note TEXT,
  created_at TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS duplicate_decisions (
  cleaned_hash TEXT PRIMARY KEY,
  decision TEXT NOT NULL,
  keep_job_id TEXT REFERENCES jobs(id),
  note TEXT,
  decided_at TEXT NOT NULL,
  created_at TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS settings (
  key TEXT PRIMARY KEY,
  value TEXT NOT NULL,
  updated_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%SZ','now'))
);

CREATE TABLE IF NOT EXISTS job_actions (
  id TEXT PRIMARY KEY DEFAULT (lower(hex(randomblob(8)))),
  job_id TEXT NOT NULL REFERENCES jobs(id),
  note TEXT NOT NULL DEFAULT '',
  due_date TEXT NOT NULL,
  completed_at TEXT,
  snoozed_until TEXT,
  created_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%SZ','now')),
  updated_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%SZ','now'))
);

CREATE TABLE IF NOT EXISTS data_quality_reviews (
  job_id TEXT PRIMARY KEY REFERENCES jobs(id) ON DELETE CASCADE,
  reviewed_at TEXT NOT NULL,
  note TEXT NOT NULL DEFAULT ''
);

CREATE TABLE IF NOT EXISTS sites (
  id TEXT PRIMARY KEY DEFAULT (lower(hex(randomblob(8)))),
  origin TEXT UNIQUE NOT NULL,
  url TEXT NOT NULL,
  company_name TEXT,
  company_website TEXT,
  jobs_url TEXT,
  company_description TEXT NOT NULL DEFAULT '',
  page_title TEXT NOT NULL DEFAULT '',
  interval_days INTEGER NOT NULL DEFAULT 14,
  last_reviewed_at TEXT,
  next_review_at TEXT,
  note TEXT NOT NULL DEFAULT '',
  state TEXT NOT NULL DEFAULT 'not_reviewed',
  added_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%SZ','now')),
  created_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%SZ','now')),
  updated_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%SZ','now'))
);

CREATE TABLE IF NOT EXISTS llm_requests (
  id TEXT PRIMARY KEY,
  job_id TEXT NOT NULL REFERENCES jobs(id) ON DELETE CASCADE,
  request_type TEXT NOT NULL DEFAULT 'extract',
  status TEXT NOT NULL DEFAULT 'queued',
  attempt INTEGER NOT NULL DEFAULT 1,
  model TEXT,
  error TEXT,
  created_at TEXT NOT NULL,
  started_at TEXT,
  finished_at TEXT,
  UNIQUE(job_id, request_type)
);

CREATE INDEX IF NOT EXISTS idx_llm_requests_status_created
  ON llm_requests (status, created_at);

CREATE INDEX IF NOT EXISTS idx_llm_requests_job
  ON llm_requests (job_id);

CREATE TABLE IF NOT EXISTS llm_request_attempts (
  id TEXT PRIMARY KEY,
  request_id TEXT NOT NULL REFERENCES llm_requests(id) ON DELETE CASCADE,
  job_id TEXT NOT NULL REFERENCES jobs(id) ON DELETE CASCADE,
  request_type TEXT NOT NULL,
  attempt INTEGER NOT NULL,
  status TEXT NOT NULL,
  model_requested TEXT,
  model_returned TEXT,
  response_format TEXT,
  base_url TEXT,
  started_at TEXT NOT NULL,
  finished_at TEXT,
  duration_ms INTEGER,
  error TEXT,
  response_preview TEXT,
  prompt_chars INTEGER,
  response_chars INTEGER
);

CREATE INDEX IF NOT EXISTS idx_llm_request_attempts_request
  ON llm_request_attempts (request_id, started_at);

CREATE INDEX IF NOT EXISTS idx_llm_request_attempts_job
  ON llm_request_attempts (job_id, started_at);
`;

// ------------------------------------------------------------------
// Helpers
// ------------------------------------------------------------------

export function defaultDbPath() {
  return process.env.JOBHUNT_DB_PATH || join(appConfigDir(), 'jobhunt.db');
}

export function appConfigDir() {
  return process.env.JOBHUNT_CONFIG_DIR || join(homedir(), '.config', 'jobhunt');
}

export function defaultLlmDebugLogPath() {
  return process.env.JOBHUNT_LLM_DEBUG_LOG_PATH || join(appConfigDir(), 'jobhunt-llm-debug.log');
}

function nowIso() {
  return new Date().toISOString();
}

function makeId(prefix) {
  return `${prefix}_${randomBytes(16).toString('hex')}`;
}

function truncateText(value, limit = 2000) {
  if (value == null) return null;
  const text = String(value);
  return text.length > limit ? text.slice(0, limit) : text;
}

function hashText(value) {
  return createHash('sha256').update(value, 'utf8').digest('hex');
}

function normalizeDuplicateText(value) {
  return String(value || '').toLowerCase().replace(/&/g, ' and ').replace(/[^a-z0-9]+/g, ' ').trim();
}

function companyDomainScore(company, url) {
  if (!company || !url) return 0;
  let hostname;
  try {
    hostname = new URL(url).hostname.toLowerCase();
  } catch {
    return 0;
  }
  hostname = hostname.replace(/^www\./, '');
  const companyText = normalizeDuplicateText(company);
  const companyCompact = companyText.replace(/\s+/g, '');
  if (!companyCompact) return 0;

  const labels = hostname.split('.').filter(Boolean);
  const registrable = labels.length >= 2 ? labels[labels.length - 2] : labels[0] || '';
  const hostCompact = labels.join('');

  if (registrable === companyCompact) return 100;
  if (labels.includes(companyCompact)) return 90;
  if (hostCompact === companyCompact) return 85;
  if (companyCompact.length >= 4 && labels.some(label => label.includes(companyCompact))) return 70;
  if (companyCompact.length >= 4 && hostCompact.includes(companyCompact)) return 60;

  const companyTokens = companyText.split(/\s+/).filter(t => t.length >= 3);
  if (companyTokens.length && companyTokens.some(token => labels.includes(token))) return 50;
  return 0;
}

function sourceHostname(url) {
  try {
    return new URL(url).hostname.toLowerCase().replace(/^www\./, '');
  } catch {
    return '';
  }
}

const DUPLICATE_DESCRIPTION_STOP_WORDS = new Set([
  'about', 'above', 'across', 'after', 'again', 'against', 'also', 'and', 'another', 'apply',
  'because', 'been', 'before', 'being', 'benefits', 'between', 'candidate', 'careers', 'company',
  'could', 'description', 'each', 'employment', 'equal', 'every', 'from', 'have', 'hiring',
  'into', 'including', 'jobs', 'listed', 'looking', 'more', 'must', 'other', 'over', 'position',
  'posted', 'posting', 'remote', 'requirements', 'responsibilities', 'role', 'same', 'seeking',
  'should', 'team', 'than', 'that', 'their', 'there', 'this', 'through', 'with', 'will', 'work',
  'working', 'would', 'years', 'your',
]);

function duplicateDescriptionTokens(value) {
  return new Set(normalizeDuplicateText(value)
    .split(/\s+/)
    .filter(token => token.length >= 4 && !DUPLICATE_DESCRIPTION_STOP_WORDS.has(token)));
}

function duplicateDescriptionSimilarity(left, right) {
  const leftTokens = duplicateDescriptionTokens(left);
  const rightTokens = duplicateDescriptionTokens(right);
  const smaller = Math.min(leftTokens.size, rightTokens.size);
  if (smaller < 8) return null;
  let intersection = 0;
  for (const token of leftTokens) {
    if (rightTokens.has(token)) intersection++;
  }
  return intersection / smaller;
}

function knownValue(value) {
  const normalized = normalizeDuplicateText(value);
  return normalized && normalized !== 'unknown' ? normalized : '';
}

function duplicateCriticalFieldsMatch(left, right) {
  for (const field of ['location', 'remote_type', 'employment_type', 'seniority']) {
    const leftValue = knownValue(left[field]);
    const rightValue = knownValue(right[field]);
    if (leftValue && rightValue && leftValue !== rightValue) return false;
  }

  for (const field of ['salary_currency', 'salary_min', 'salary_max']) {
    if (left[field] != null && right[field] != null && left[field] !== right[field]) return false;
  }
  return true;
}

function duplicateEvidenceMatch(left, right) {
  if (!duplicateCriticalFieldsMatch(left, right)) return null;
  const descriptionSimilarity = duplicateDescriptionSimilarity(left.cleaned_description, right.cleaned_description);
  if (descriptionSimilarity != null && descriptionSimilarity < 0.5) return null;
  return { descriptionSimilarity };
}

function duplicateDetectionNote(keep, job, evidence) {
  const parts = [`preferred ${keep.source_hostname} over ${job.source_hostname}`];
  if (evidence.descriptionSimilarity != null) {
    parts.push(`description similarity ${evidence.descriptionSimilarity.toFixed(2)}`);
  }
  return parts.join('; ');
}

// Produces compact JSON with all object keys sorted recursively,
// matching Python's json.dumps(x, sort_keys=True, separators=(",",":")).
function sortedJson(value) {
  if (Array.isArray(value)) {
    return '[' + value.map(sortedJson).join(',') + ']';
  }
  if (value !== null && typeof value === 'object') {
    const keys = Object.keys(value).sort();
    return '{' + keys.map(k => JSON.stringify(k) + ':' + sortedJson(value[k])).join(',') + '}';
  }
  return JSON.stringify(value);
}

function rawHash(capture) {
  const payload = {
    canonical_url: capture.canonical_url ?? null,
    selected_text: capture.selected_text ?? '',
    structured_data: capture.structured_data ?? [],
    url: capture.url,
    visible_text: capture.visible_text ?? '',
  };
  // Keys sorted alphabetically (canonical_url, selected_text, structured_data, url, visible_text)
  return hashText(sortedJson(payload));
}

function inferSiteCompanyName(origin, pageTitle) {
  if (pageTitle && pageTitle.trim()) return pageTitle.trim();
  try {
    const url = new URL(origin);
    let host = url.hostname || origin;
    if (host.startsWith('www.')) host = host.slice(4);
    const part = host.split('.')[0];
    return part.replace(/-/g, ' ').replace(/\b\w/g, c => c.toUpperCase());
  } catch {
    return origin;
  }
}

function inferCompanyWebsite(origin, url) {
  try {
    const parsed = new URL(url || origin);
    return `${parsed.protocol}//${parsed.host}`;
  } catch {
    return null;
  }
}

function normalizeSiteState(state) {
  if (!state) return 'not_reviewed';
  const normalized = state.trim().toLowerCase();
  if (SITE_STATES.has(normalized)) return normalized;
  const legacy = { none: 'not_reviewed', never: 'not_reviewed', today: 'reviewed', soon: 'reviewed', overdue: 'reviewed' };
  return legacy[normalized] ?? 'not_reviewed';
}

// Simple transaction wrapper
function withTransaction(db, fn) {
  db.exec('BEGIN IMMEDIATE');
  try {
    const result = fn();
    db.exec('COMMIT');
    return result;
  } catch (e) {
    try { db.exec('ROLLBACK'); } catch { /* ignore rollback errors */ }
    throw e;
  }
}

// ------------------------------------------------------------------
// Connection / init
// ------------------------------------------------------------------

const _connections = new Map();

export function connect(dbPath) {
  const resolved = resolve(dbPath || defaultDbPath());
  migrateLegacyRuntimeFiles(resolved);
  if (_connections.has(resolved)) return _connections.get(resolved);
  mkdirSync(dirname(resolved), { recursive: true });
  const db = new DatabaseSync(resolved);
  db.exec('PRAGMA foreign_keys = ON');
  db.exec('PRAGMA journal_mode = WAL');
  _connections.set(resolved, db);
  return db;
}

function migrateLegacyRuntimeFiles(resolvedDbPath) {
  if (process.env.JOBHUNT_DB_PATH) return;
  const targetDbPath = resolve(defaultDbPath());
  if (resolvedDbPath !== targetDbPath || existsSync(targetDbPath)) return;

  const legacyDbPath = resolve('.data/jobhunt.db');
  if (!existsSync(legacyDbPath)) return;

  mkdirSync(dirname(targetDbPath), { recursive: true });
  try {
    const legacyDb = new DatabaseSync(legacyDbPath);
    legacyDb.exec('PRAGMA wal_checkpoint(TRUNCATE)');
    legacyDb.close();
  } catch {
    // If checkpointing fails, still copy the main DB; it is better than starting empty.
  }
  copyFileSync(legacyDbPath, targetDbPath);

  const legacyLogPath = resolve('.data/jobhunt-llm-debug.log');
  const targetLogPath = defaultLlmDebugLogPath();
  if (existsSync(legacyLogPath) && !existsSync(targetLogPath)) {
    copyFileSync(legacyLogPath, targetLogPath);
  }
}

export function initDb(dbPath) {
  const db = connect(dbPath);
  // Run each statement separately since node:sqlite exec doesn't support multiple statements well with some pragmas
  db.exec(SCHEMA);
  migrateSchema(db);
  return db;
}

function tableColumns(db, tableName) {
  return new Set(db.prepare(`PRAGMA table_info(${tableName})`).all().map(r => r.name));
}

function migrateSchema(db) {
  // Sites columns
  const siteColumns = tableColumns(db, 'sites');
  const siteColsToAdd = [
    ['company_name', 'TEXT'],
    ['company_website', 'TEXT'],
    ['jobs_url', 'TEXT'],
    ['company_description', "TEXT NOT NULL DEFAULT ''"],
    ['state', "TEXT NOT NULL DEFAULT 'not_reviewed'"],
    ['added_at', 'TEXT'],
  ];
  for (const [col, def] of siteColsToAdd) {
    if (!siteColumns.has(col)) {
      db.exec(`ALTER TABLE sites ADD COLUMN ${col} ${def}`);
      siteColumns.add(col);
    }
  }
  backfillSitesMetadata(db, siteColumns);

  // Jobs columns
  const jobColumns = tableColumns(db, 'jobs');
  const jobColsToAdd = [
    ['salary_note', 'TEXT'],
    ['job_number', 'INTEGER'],
    ['rating', 'INTEGER CHECK(rating BETWEEN 1 AND 5)'],
    ['extraction_model', 'TEXT'],
    ['application_url', 'TEXT'],
    ['extraction_confidence', 'REAL'],
    ['last_opened_at', 'TEXT'],
    ['manual_overrides', "TEXT NOT NULL DEFAULT '[]'"],
    ['fit_score', 'INTEGER'],
    ['fit_status', "TEXT NOT NULL DEFAULT 'none'"],
    ['fit_score_json', 'TEXT'],
  ];
  for (const [col, def] of jobColsToAdd) {
    if (!jobColumns.has(col)) {
      db.exec(`ALTER TABLE jobs ADD COLUMN ${col} ${def}`);
      jobColumns.add(col);
    }
  }
  backfillJobNumbers(db, jobColumns);
  migrateLegacyStatuses(db);
  db.exec('CREATE UNIQUE INDEX IF NOT EXISTS idx_jobs_job_number ON jobs(job_number)');

  const attemptColumns = tableColumns(db, 'llm_request_attempts');
  if (!attemptColumns.has('response_format')) {
    db.exec('ALTER TABLE llm_request_attempts ADD COLUMN response_format TEXT');
  }
}

function backfillSitesMetadata(db, columns) {
  if (!columns.has('origin')) return;
  if (columns.has('added_at')) {
    db.exec("UPDATE sites SET added_at = COALESCE(added_at, created_at)");
  }
  if (columns.has('state')) {
    db.exec(`UPDATE sites SET state = CASE
      WHEN LOWER(COALESCE(state, '')) IN ('reviewed', 'exclude', 'not_reviewed') THEN LOWER(COALESCE(state, ''))
      WHEN last_reviewed_at IS NOT NULL THEN 'reviewed'
      ELSE 'not_reviewed' END`);
  }
  if (columns.has('company_name')) {
    const rows = db.prepare("SELECT rowid, origin, page_title FROM sites WHERE company_name IS NULL OR company_name = ''").all();
    const stmt = db.prepare("UPDATE sites SET company_name = ? WHERE rowid = ?");
    for (const row of rows) {
      stmt.run(inferSiteCompanyName(row.origin, row.page_title), row.rowid);
    }
  }
  if (columns.has('company_website')) {
    db.exec("UPDATE sites SET company_website = COALESCE(company_website, CASE WHEN instr(origin, '://') > 0 THEN origin ELSE NULL END)");
  }
  if (columns.has('jobs_url')) {
    db.exec("UPDATE sites SET jobs_url = COALESCE(jobs_url, url)");
  }
  if (columns.has('company_description')) {
    db.exec("UPDATE sites SET company_description = COALESCE(NULLIF(company_description, ''), page_title, '')");
  }
}

function backfillJobNumbers(db, columns) {
  if (!columns.has('job_number')) return;
  const rows = db.prepare("SELECT id, job_number FROM jobs ORDER BY created_at, id").all();
  let nextNumber = 1;
  const usedNumbers = new Set(rows.filter(r => r.job_number != null).map(r => r.job_number));
  const stmt = db.prepare("UPDATE jobs SET job_number = ? WHERE id = ?");
  for (const row of rows) {
    if (row.job_number != null) {
      nextNumber = Math.max(nextNumber, Number(row.job_number) + 1);
      continue;
    }
    while (usedNumbers.has(nextNumber)) nextNumber++;
    stmt.run(nextNumber, row.id);
    usedNumbers.add(nextNumber);
    nextNumber++;
  }
}

function migrateLegacyStatuses(db) {
  for (const [legacy, canonical] of Object.entries(LEGACY_STATUS_MAP)) {
    db.prepare("UPDATE jobs SET status = ? WHERE status = ?").run(canonical, legacy);
  }
}

// ------------------------------------------------------------------
// Settings
// ------------------------------------------------------------------

export function getSettings(db) {
  const rows = db.prepare("SELECT key, value FROM settings").all();
  const result = { ...SETTINGS_DEFAULTS };
  for (const row of rows) {
    result[row.key] = row.value;
  }
  return result;
}

export function setSetting(db, key, value) {
  db.prepare("INSERT INTO settings (key, value) VALUES (?, ?) ON CONFLICT(key) DO UPDATE SET value=excluded.value, updated_at=strftime('%Y-%m-%dT%H:%M:%SZ','now')").run(key, value);
}

// ------------------------------------------------------------------
// Capture insertion
// ------------------------------------------------------------------

function findOriginalCaptureForUrl(db, url, canonicalUrl) {
  // Return the ORIGINAL (lowest job_number) capture for this URL so updates
  // always target the canonical job, not a later duplicate.
  const q = `SELECT captures.id, captures.url, captures.canonical_url,
    captures.cleaned_description, captures.raw_hash, jobs.id AS job_id
    FROM captures JOIN jobs ON jobs.capture_id = captures.id
    WHERE {where} ORDER BY jobs.job_number ASC LIMIT 1`;
  let row = db.prepare(q.replace('{where}', 'captures.url = ?')).get(url);
  if (!row && canonicalUrl) {
    row = db.prepare(q.replace('{where}', 'captures.canonical_url = ?')).get(canonicalUrl);
  }
  return row || null;
}

function recordDuplicateNote(db, captureId, note, occurredAt, createdAt) {
  if (!note || !note.trim()) return;
  const row = db.prepare("SELECT id FROM jobs WHERE capture_id = ? LIMIT 1").get(captureId);
  if (!row) return;
  db.prepare("INSERT INTO events (id, job_id, event_type, note, occurred_at, created_at) VALUES (?, ?, 'note_added', ?, ?, ?)").run(makeId('evt'), row.id, note, occurredAt, createdAt);
}

function recordRecaptureEvent(db, jobId, occurredAt, createdAt) {
  db.prepare("INSERT INTO events (id, job_id, event_type, note, occurred_at, created_at) VALUES (?, ?, 'recaptured', NULL, ?, ?)")
    .run(makeId('evt'), jobId, occurredAt, createdAt);
}

function findDuplicateJobId(db, cleanedHash, url, canonicalUrl) {
  if (!cleanedHash) return null;
  const row = db.prepare(`SELECT jobs.id FROM jobs
    JOIN captures ON captures.id = jobs.capture_id
    WHERE captures.cleaned_hash = ?
      AND captures.url != ?
      AND COALESCE(captures.canonical_url, '') != COALESCE(?, '')
    ORDER BY captures.created_at LIMIT 1`).get(cleanedHash, url, canonicalUrl ?? '');
  return row ? row.id : null;
}

function nextJobNumber(db) {
  const row = db.prepare("SELECT COALESCE(MAX(job_number), 0) + 1 AS n FROM jobs").get();
  return Number(row.n);
}

export function insertCapture(capture, dbPath) {
  initDb(dbPath);
  const db = connect(dbPath);

  const cleaned = cleanDescription({
    selectedText: capture.selected_text || '',
    visibleText: capture.visible_text || '',
    structuredData: capture.structured_data || [],
  });
  const rHash = rawHash(capture);
  const cHash = cleaned ? hashText(cleaned) : null;
  const now = nowIso();
  const capturedAt = capture.captured_at instanceof Date
    ? capture.captured_at.toISOString()
    : (capture.captured_at || now);

  return withTransaction(db, () => {
    // Check for same URL — always target the original job, not the latest duplicate.
    const exactMatch = findOriginalCaptureForUrl(db, capture.url, capture.canonical_url);
    const cleanedChanged = exactMatch && (exactMatch.cleaned_description || '') !== cleaned;
    const rawChanged = exactMatch && exactMatch.raw_hash !== rHash;
    if (exactMatch && (cleanedChanged || rawChanged)) {
      try {
        db.prepare(`UPDATE captures SET
          selected_text=?, visible_text=?, cleaned_description=?, structured_data_json=?,
          raw_hash=?, cleaned_hash=?, url=?, canonical_url=?, page_title=?, captured_at=?
          WHERE id=?`).run(
          capture.selected_text || null,
          capture.visible_text || null,
          cleaned,
          JSON.stringify(capture.structured_data || []),
          rHash, cHash,
          capture.url, capture.canonical_url || null,
          capture.page_title, capturedAt, exactMatch.id
        );
        db.prepare(`UPDATE jobs SET extraction_status='pending', extraction_error=NULL,
          duplicate_of_job_id=NULL, duplicate_confidence=NULL, updated_at=?
          WHERE id=?`).run(now, exactMatch.job_id);
        recordRecaptureEvent(db, exactMatch.job_id, capturedAt, now);
        recordDuplicateNote(db, exactMatch.id, capture.user_note, capturedAt, now);
        return { capture_id: exactMatch.id, duplicate: false, duplicate_of_job_id: null };
      } catch (e) {
        if (!e.message.includes('UNIQUE')) throw e;
        // raw_hash conflict: this content is already stored in another capture.
        // Still update cleaned_description on the original job (cleaning may have improved)
        // and re-queue extraction, but keep the existing raw content.
        if (cleanedChanged) {
          db.prepare("UPDATE captures SET cleaned_description=?, cleaned_hash=? WHERE id=?")
            .run(cleaned, cHash, exactMatch.id);
        }
        db.prepare(`UPDATE jobs SET extraction_status='pending', extraction_error=NULL, updated_at=? WHERE id=?`)
          .run(now, exactMatch.job_id);
        recordRecaptureEvent(db, exactMatch.job_id, capturedAt, now);
        return { capture_id: exactMatch.id, duplicate: false, duplicate_of_job_id: null };
      }
    }

    // Hash dedup
    const existing = db.prepare("SELECT id FROM captures WHERE raw_hash = ?").get(rHash);
    if (existing) {
      recordDuplicateNote(db, existing.id, capture.user_note, capturedAt, now);
      return { capture_id: existing.id, duplicate: true, duplicate_of_job_id: null };
    }

    const duplicateOfJobId = findDuplicateJobId(db, cHash, capture.url, capture.canonical_url);
    const captureId = makeId('cap');
    const jobId = makeId('job');
    const jobNumber = nextJobNumber(db);

    db.prepare(`INSERT INTO captures (id, url, canonical_url, page_title, selected_text, visible_text,
      cleaned_description, structured_data_json, user_note, raw_hash, cleaned_hash, captured_at, created_at)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`).run(
      captureId, capture.url, capture.canonical_url || null, capture.page_title,
      capture.selected_text || null, capture.visible_text || null,
      cleaned, JSON.stringify(capture.structured_data || []), capture.user_note || null,
      rHash, cHash, capturedAt, now
    );

    db.prepare(`INSERT INTO jobs (id, job_number, capture_id, status, extraction_status,
      duplicate_of_job_id, duplicate_confidence, created_at, updated_at)
      VALUES (?, ?, ?, 'saved', 'pending', ?, ?, ?, ?)`).run(
      jobId, jobNumber, captureId, duplicateOfJobId, duplicateOfJobId ? 1.0 : null, now, now
    );

    db.prepare(`INSERT INTO events (id, job_id, event_type, note, occurred_at, created_at)
      VALUES (?, ?, 'captured', NULL, ?, ?)`).run(makeId('evt'), jobId, capturedAt, now);

    return { capture_id: captureId, duplicate: false, duplicate_of_job_id: duplicateOfJobId };
  });
}

// ------------------------------------------------------------------
// LLM queue helpers
// ------------------------------------------------------------------

export const MAX_LLM_ATTEMPTS = 3;
const RETRY_LIMIT_ERROR = `Retry limit reached (${MAX_LLM_ATTEMPTS} attempts).`;

function failRetryExhaustedRequests(db, dbPath = null) {
  const now = nowIso();
  const exhausted = db.prepare(`SELECT id, job_id, request_type FROM llm_requests
    WHERE (status='queued' AND attempt > ?) OR (status='failed' AND attempt >= ?)`).all(MAX_LLM_ATTEMPTS, MAX_LLM_ATTEMPTS);
  if (!exhausted.length) return 0;
  const requestIds = exhausted.map(r => r.id);
  const placeholders = requestIds.map(() => '?').join(',');
  db.prepare(`UPDATE llm_requests SET status='failed', attempt=?, error=?, started_at=NULL, finished_at=?
    WHERE id IN (${placeholders})`).run(MAX_LLM_ATTEMPTS, RETRY_LIMIT_ERROR, now, ...requestIds);
  for (const row of exhausted) {
    if (dbPath) {
      const attemptId = startLlmRequestAttempt(dbPath, row.id, {});
      finishLlmRequestAttempt(dbPath, attemptId, { status: 'retry_exhausted', error: RETRY_LIMIT_ERROR });
    }
    if (row.request_type === 'fit_score') {
      db.prepare("UPDATE jobs SET fit_status='failed', fit_score_json=?, updated_at=? WHERE id=?")
        .run(JSON.stringify({ error: RETRY_LIMIT_ERROR }), now, row.job_id);
    } else {
      db.prepare("UPDATE jobs SET extraction_status='failed', extraction_error=?, updated_at=? WHERE id=?")
        .run(RETRY_LIMIT_ERROR, now, row.job_id);
    }
  }
  return exhausted.length;
}

function fetchLlmRequests(db, statuses, limit, { processableOnly = false, runningFirst = false } = {}) {
  if (!statuses.length) return [];
  const placeholders = statuses.map(() => '?').join(',');
  const limitClause = limit != null ? ' LIMIT ?' : '';
  const processableClause = processableOnly
    ? `AND ((r.status='queued' AND r.attempt <= ${MAX_LLM_ATTEMPTS}) OR (r.status='failed' AND r.attempt < ${MAX_LLM_ATTEMPTS}))`
    : '';
  const orderClause = runningFirst
    ? "CASE r.status WHEN 'running' THEN 0 WHEN 'queued' THEN 1 WHEN 'failed' THEN 2 ELSE 3 END, r.created_at"
    : 'r.created_at';
  const params = [...statuses];
  if (limit != null) params.push(limit);
  return db.prepare(`
    SELECT r.id, r.job_id, jobs.job_number, r.status, r.request_type,
      r.created_at, r.started_at, r.finished_at, r.error, r.attempt, r.model,
      jobs.company, jobs.title,
      COALESCE(captures.canonical_url, captures.url) AS source_url,
      latest_attempt.status AS last_attempt_status,
      latest_attempt.model_requested AS last_attempt_model_requested,
      latest_attempt.model_returned AS last_attempt_model_returned,
      latest_attempt.response_format AS last_attempt_response_format,
      latest_attempt.duration_ms AS last_attempt_duration_ms,
      latest_attempt.error AS last_attempt_error,
      latest_attempt.response_preview AS last_attempt_response_preview
    FROM llm_requests r
    JOIN jobs ON jobs.id = r.job_id
    JOIN captures ON captures.id = jobs.capture_id
    LEFT JOIN llm_request_attempts latest_attempt
      ON latest_attempt.id = (
        SELECT a.id FROM llm_request_attempts a
        WHERE a.request_id = r.id
        ORDER BY a.started_at DESC
        LIMIT 1
      )
    WHERE r.status IN (${placeholders})
    ${processableClause}
    ORDER BY ${orderClause}${limitClause}`).all(...params);
}

export function getLlmRequestState(requestId, dbPath) {
  const db = initDb(dbPath);
  return db.prepare(`SELECT lr.id, lr.job_id, lr.request_type, lr.status, lr.attempt,
    lr.started_at, lr.finished_at, lr.error, lr.model,
    j.job_number, j.company, j.title
    FROM llm_requests lr JOIN jobs j ON j.id = lr.job_id
    WHERE lr.id=?`).get(requestId) || null;
}

function debugLevelEnabled(db, level) {
  const settings = getSettings(db);
  const value = String(settings.llm_debug_level || 'errors').toLowerCase();
  if (value === 'off' || value === 'false' || value === 'none') return false;
  if (level === 'full') return value === 'full';
  return value === 'errors' || value === 'full';
}

function appendLlmDebugLine(dbPath, payload) {
  try {
    const filePath = resolve(defaultLlmDebugLogPath());
    mkdirSync(dirname(filePath), { recursive: true });
    appendFileSync(filePath, `${JSON.stringify({ ts: nowIso(), ...payload })}\n`, 'utf8');
  } catch {
    // Debug logging must never break queue processing.
  }
}

/**
 * @param {{ baseUrl?: string|null, modelRequested?: string|null, promptChars?: number|null }} [details]
 */
export function startLlmRequestAttempt(dbPath, requestId, details = {}) {
  const { baseUrl, modelRequested, promptChars } = details;
  const db = initDb(dbPath);
  if (!debugLevelEnabled(db, 'errors')) return null;
  const request = db.prepare("SELECT id, job_id, request_type, attempt FROM llm_requests WHERE id=?").get(requestId);
  if (!request) return null;
  const id = makeId('llma');
  const now = nowIso();
  db.prepare(`INSERT INTO llm_request_attempts
    (id, request_id, job_id, request_type, attempt, status, model_requested, base_url, started_at, prompt_chars)
    VALUES (?, ?, ?, ?, ?, 'started', ?, ?, ?, ?)`)
    .run(id, request.id, request.job_id, request.request_type, request.attempt, modelRequested || null, baseUrl || null, now, promptChars ?? null);
  return id;
}

/**
 * @param {{ status: string, modelReturned?: string|null, responseFormat?: string|null, error?: string|null, responsePreview?: string|null, responseChars?: number|null }} details
 */
export function finishLlmRequestAttempt(dbPath, attemptId, details) {
  if (!attemptId) return;
  const { status, modelReturned, responseFormat, error, responsePreview, responseChars } = details;
  const db = initDb(dbPath);
  const existing = db.prepare("SELECT started_at FROM llm_request_attempts WHERE id=?").get(attemptId);
  if (!existing) return;
  const now = nowIso();
  const startedMs = new Date(existing.started_at).getTime();
  const durationMs = Number.isFinite(startedMs) ? Math.max(0, Date.now() - startedMs) : null;
  const shouldKeepResponse = debugLevelEnabled(db, 'full') || (status === 'failed' && debugLevelEnabled(db, 'errors'));
  db.prepare(`UPDATE llm_request_attempts SET status=?, model_returned=?, response_format=?, finished_at=?, duration_ms=?,
    error=?, response_preview=?, response_chars=? WHERE id=?`)
    .run(
      status,
      modelReturned || null,
      responseFormat || null,
      now,
      durationMs,
      truncateText(error, 2000),
      shouldKeepResponse ? truncateText(responsePreview, 4000) : null,
      responseChars ?? null,
      attemptId,
    );
  if (status === 'failed' || status === 'retry_exhausted') {
    appendLlmDebugLine(dbPath, { event: 'llm_attempt_failed', attempt_id: attemptId, status, model_returned: modelReturned || null, error: truncateText(error, 500) });
  }
}

function upsertLlmRequest(db, jobId, requestType = 'extract', { resetAttempts = false } = {}) {
  const now = nowIso();
  const existing = db.prepare("SELECT id, status, attempt FROM llm_requests WHERE job_id = ? AND request_type = ?").get(jobId, requestType);
  if (!existing) {
    const requestId = makeId('llm');
    db.prepare("INSERT INTO llm_requests (id, job_id, request_type, status, attempt, created_at) VALUES (?, ?, ?, 'queued', 1, ?)").run(requestId, jobId, requestType, now);
    return requestId;
  }
  if (existing.status === 'running') return existing.id;
  if (resetAttempts) {
    db.prepare(`UPDATE llm_requests SET status='queued', attempt=1, error=NULL, model=NULL,
      started_at=NULL, finished_at=NULL, created_at=? WHERE id=?`).run(now, existing.id);
    return existing.id;
  }
  if (existing.status === 'queued' || existing.status === 'failed') {
    const nextAttempt = Math.min(Number(existing.attempt || 1) + 1, MAX_LLM_ATTEMPTS);
    if (Number(existing.attempt || 1) >= MAX_LLM_ATTEMPTS) {
      db.prepare("UPDATE llm_requests SET status='failed', attempt=?, error=?, started_at=NULL, finished_at=? WHERE id=?")
        .run(MAX_LLM_ATTEMPTS, RETRY_LIMIT_ERROR, now, existing.id);
      return existing.id;
    }
    db.prepare(`UPDATE llm_requests SET status='queued', attempt=?, error=NULL, model=NULL,
      started_at=NULL, finished_at=NULL, created_at=? WHERE id=?`).run(nextAttempt, now, existing.id);
    return existing.id;
  }
  db.prepare(`UPDATE llm_requests SET status='queued', attempt=1, error=NULL, model=NULL,
    started_at=NULL, finished_at=NULL, created_at=? WHERE id=?`).run(now, existing.id);
  return existing.id;
}

export function resetLlmRequestsForManualRun(dbPath, requestIds) {
  if (!requestIds.length) return 0;
  const db = initDb(dbPath);
  const now = nowIso();
  const placeholders = requestIds.map(() => '?').join(',');
  const result = db.prepare(`UPDATE llm_requests SET status='queued', attempt=1, error=NULL,
    model=NULL, started_at=NULL, finished_at=NULL, created_at=?
    WHERE id IN (${placeholders}) AND status IN ('queued','failed')`).run(now, ...requestIds);
  return result.changes;
}

export function markLlmRequestRunning(requestId, dbPath) {
  const db = connect(dbPath);
  const now = nowIso();
  failRetryExhaustedRequests(db, dbPath);
  const result = db.prepare(`UPDATE llm_requests SET status='running',
      attempt=CASE WHEN status='failed' THEN attempt+1 ELSE attempt END,
      started_at=?, finished_at=NULL, error=NULL
    WHERE id=?
      AND ((status='queued' AND attempt <= ?) OR (status='failed' AND attempt < ?))`)
    .run(now, requestId, MAX_LLM_ATTEMPTS, MAX_LLM_ATTEMPTS);
  return result.changes > 0;
}

export function cancelLlmRequest(requestId, dbPath) {
  const db = connect(dbPath);
  const now = nowIso();
  const result = db.prepare("UPDATE llm_requests SET status='canceled', finished_at=? WHERE id=? AND status IN ('queued','running','failed')").run(now, requestId);
  return result.changes > 0;
}

export function cancelAllLlmRequests(dbPath, statuses = ['queued', 'running', 'failed']) {
  const db = connect(dbPath);
  if (!statuses.length) return 0;
  const placeholders = statuses.map(() => '?').join(',');
  const now = nowIso();
  const result = db.prepare(`UPDATE llm_requests SET status='canceled', finished_at=? WHERE status IN (${placeholders})`).run(now, ...statuses);
  return result.changes;
}

export function getOutstandingLlmRequests(dbPath, statuses = ['queued', 'running', 'failed'], limit = null) {
  if (!statuses.length) return [];
  const db = initDb(dbPath);
  return fetchLlmRequests(db, statuses, limit, { runningFirst: true });
}

export function getLlmRequestsByIds(requestIds, dbPath) {
  if (!requestIds.length) return [];
  const db = initDb(dbPath);
  const placeholders = requestIds.map(() => '?').join(',');
  const rows = db.prepare(`SELECT lr.id, lr.job_id, lr.request_type, lr.status, lr.attempt,
    lr.created_at, lr.started_at, lr.finished_at, lr.error, lr.model,
    j.company, j.title, j.job_number, c.canonical_url AS source_url
    FROM llm_requests lr JOIN jobs j ON j.id = lr.job_id JOIN captures c ON c.id = j.capture_id
    WHERE lr.id IN (${placeholders})`).all(...requestIds);
  // Re-sort to caller's requested order (matches Python behavior)
  const idOrder = Object.fromEntries(requestIds.map((id, i) => [id, i]));
  return rows.sort((a, b) => (idOrder[a.id] ?? 999) - (idOrder[b.id] ?? 999));
}

export function getLlmRequestAttempts(dbPath, requestId) {
  const db = initDb(dbPath);
  return db.prepare(`SELECT id, request_id, job_id, request_type, attempt, status,
    model_requested, model_returned, response_format, base_url, started_at, finished_at, duration_ms,
    error, response_preview, prompt_chars, response_chars
    FROM llm_request_attempts
    WHERE request_id=?
    ORDER BY started_at DESC`).all(requestId);
}

export function countUnqueuedPendingJobs(dbPath) {
  const db = initDb(dbPath);
  const row = db.prepare(`SELECT COUNT(*) AS n FROM jobs
    WHERE jobs.extraction_status IN ('pending','failed')
    AND jobs.id NOT IN (SELECT job_id FROM llm_requests WHERE status IN ('queued','running','failed'))`).get();
  return row ? Number(row.n) : 0;
}

export function enqueueAllPendingJobs(dbPath) {
  const db = initDb(dbPath);
  return withTransaction(db, () => {
    const rows = db.prepare(`SELECT jobs.id AS job_id FROM jobs JOIN captures ON captures.id=jobs.capture_id
      WHERE jobs.extraction_status IN ('pending','failed')
      AND jobs.id NOT IN (SELECT job_id FROM llm_requests WHERE status IN ('queued','running','failed'))
      ORDER BY captures.created_at`).all();
    for (const row of rows) upsertLlmRequest(db, row.job_id, 'extract');
    return rows.length;
  });
}

const STALE_RUNNING_SECONDS = 600;

function requeueStaleRunningRequests(db, olderThanSeconds) {
  const rows = db.prepare("SELECT id, started_at FROM llm_requests WHERE status='running'").all();
  if (!rows.length) return 0;
  const cutoff = Date.now() - olderThanSeconds * 1000;
  let count = 0;
  for (const row of rows) {
    let isStale;
    if (!row.started_at) {
      isStale = true;
    } else {
      const startedMs = new Date(row.started_at).getTime();
      isStale = isNaN(startedMs) || startedMs <= cutoff;
    }
    if (isStale) {
      db.prepare(`UPDATE llm_requests SET status='queued', attempt=attempt+1, started_at=NULL, finished_at=NULL,
        error='Requeued after being stuck running (worker exited before recording a result).'
        WHERE id=? AND status='running'`).run(row.id);
      count++;
    }
  }
  return count;
}

export function requeueRunningRequests(dbPath, olderThanSeconds = 0) {
  const db = initDb(dbPath);
  return requeueStaleRunningRequests(db, olderThanSeconds);
}

export function getLlmQueueForProcessing(dbPath, limit = 10) {
  if (limit <= 0) return [];
  const db = initDb(dbPath);
  requeueStaleRunningRequests(db, STALE_RUNNING_SECONDS);
  failRetryExhaustedRequests(db, dbPath);
  let processing = fetchLlmRequests(db, ['queued', 'failed'], limit, { processableOnly: true });
  if (processing.length < limit) {
    const missing = limit - processing.length;
    const rows = db.prepare(`SELECT jobs.id AS job_id FROM jobs JOIN captures ON captures.id=jobs.capture_id
      WHERE jobs.extraction_status IN ('pending','failed')
      AND jobs.id NOT IN (SELECT job_id FROM llm_requests WHERE status IN ('queued','running','failed'))
      ORDER BY captures.created_at LIMIT ?`).all(missing);
    for (const row of rows) upsertLlmRequest(db, row.job_id, 'extract');
    failRetryExhaustedRequests(db, dbPath);
    processing = fetchLlmRequests(db, ['queued', 'failed'], limit, { processableOnly: true });
  }
  return processing;
}

// ------------------------------------------------------------------
// Extraction
// ------------------------------------------------------------------

export function getPendingExtractionForJob(dbPath, jobId) {
  const db = initDb(dbPath);
  return db.prepare(`SELECT jobs.id AS job_id, captures.id AS capture_id,
    captures.url, captures.canonical_url, captures.page_title,
    COALESCE(NULLIF(captures.cleaned_description,''), NULLIF(captures.selected_text,''), captures.visible_text) AS description,
    COALESCE(captures.cleaned_description,'') || CHAR(10) || COALESCE(captures.visible_text,'') || CHAR(10) || COALESCE(captures.structured_data_json,'') AS source_text
    FROM jobs JOIN captures ON captures.id=jobs.capture_id
    WHERE jobs.id=? AND jobs.extraction_status IN ('pending','failed')`).get(jobId) || null;
}

export function markExtractionSucceeded(jobId, extracted, dbPath, requestId, model, confidence) {
  const db = connect(dbPath);
  const now = nowIso();
  const extractedJson = JSON.stringify(extracted);
  const applicationUrl = extracted.application_url || null;

  withTransaction(db, () => {
    const row = db.prepare("SELECT manual_overrides FROM jobs WHERE id=?").get(jobId);
    const overrides = new Set(JSON.parse((row?.manual_overrides) || '[]'));

    const editable = {
      company: extracted.company,
      title: extracted.title,
      location: extracted.location,
      remote_type: extracted.remote_type,
      salary_min: extracted.salary_min,
      salary_max: extracted.salary_max,
      salary_currency: extracted.salary_currency,
      salary_note: extracted.salary_note,
      employment_type: extracted.employment_type,
      seniority: extracted.seniority,
    };

    const toSet = {};
    for (const [k, v] of Object.entries(editable)) {
      if (!overrides.has(k)) toSet[k] = v ?? null;
    }
    Object.assign(toSet, {
      extracted_json: extractedJson,
      extraction_status: 'succeeded',
      extraction_error: null,
      extracted_at: now,
      updated_at: now,
      extraction_model: model ?? null,
      application_url: applicationUrl,
      extraction_confidence: confidence ?? null,
    });

    const setClause = Object.keys(toSet).map(k => `${k}=?`).join(', ');
    db.prepare(`UPDATE jobs SET ${setClause} WHERE id=?`).run(...Object.values(toSet), jobId);

    if (requestId) {
      db.prepare("UPDATE llm_requests SET status='succeeded', model=?, error=NULL, finished_at=? WHERE id=? AND status='running'").run(model ?? null, now, requestId);
    }
  });
  detectDomainDuplicateJobs(dbPath);
}

export function markExtractionFailed(jobId, error, dbPath, requestId) {
  const db = connect(dbPath);
  const now = nowIso();
  db.prepare("UPDATE jobs SET extraction_status='failed', extraction_error=?, updated_at=? WHERE id=?").run(String(error).slice(0, 2000), now, jobId);
  if (requestId) {
    db.prepare("UPDATE llm_requests SET status='failed', error=?, finished_at=? WHERE id=? AND status!='succeeded'").run(String(error).slice(0, 2000), now, requestId);
  }
}

export function resetJobExtraction(jobId, dbPath) {
  const db = connect(dbPath);
  const now = nowIso();
  const existing = db.prepare("SELECT id FROM jobs WHERE id=?").get(jobId);
  if (!existing) throw new Error(`job not found: ${jobId}`);
  db.prepare("UPDATE jobs SET extraction_status='pending', extraction_error=NULL, updated_at=? WHERE id=?").run(now, jobId);
  const requestId = upsertLlmRequest(db, jobId, 'extract', { resetAttempts: true });
  db.prepare("INSERT INTO events (id, job_id, event_type, note, occurred_at, created_at) VALUES (?, ?, 'extraction_queued', NULL, ?, ?)").run(makeId('evt'), jobId, now, now);
  return requestId;
}

// ------------------------------------------------------------------
// Fit scoring
// ------------------------------------------------------------------

export function queueFitScoreForJob(dbPath, jobId, { resetAttempts = false } = {}) {
  const db = initDb(dbPath);
  const now = nowIso();
  const existing = db.prepare("SELECT id FROM jobs WHERE id=?").get(jobId);
  if (!existing) throw new Error(`job not found: ${jobId}`);
  db.prepare("UPDATE jobs SET fit_status='pending', updated_at=? WHERE id=?").run(now, jobId);
  return upsertLlmRequest(db, jobId, 'fit_score', { resetAttempts });
}

export function getJobFitContext(dbPath, jobId) {
  const db = initDb(dbPath);
  const row = db.prepare("SELECT company, title, extracted_json, extraction_status FROM jobs WHERE id=?").get(jobId);
  if (!row || row.extraction_status !== 'succeeded' || !row.extracted_json) return null;
  try {
    const extracted = JSON.parse(row.extracted_json);
    return { company: row.company, title: row.title, extracted };
  } catch {
    return null;
  }
}

export function markFitSucceeded(jobId, fit, dbPath, requestId, model) {
  const db = connect(dbPath);
  const now = nowIso();
  const payload = { ...fit, model: model ?? null, scored_at: now };
  withTransaction(db, () => {
    db.prepare("UPDATE jobs SET fit_score=?, fit_status='succeeded', fit_score_json=?, updated_at=? WHERE id=?").run(fit.overall_score, JSON.stringify(payload), now, jobId);
    if (requestId) {
      db.prepare("UPDATE llm_requests SET status='succeeded', model=?, error=NULL, finished_at=? WHERE id=? AND status='running'").run(model ?? null, now, requestId);
    }
  });
}

export function markFitFailed(jobId, error, dbPath, requestId) {
  const db = connect(dbPath);
  const now = nowIso();
  withTransaction(db, () => {
    db.prepare("UPDATE jobs SET fit_status='failed', fit_score_json=?, updated_at=? WHERE id=?").run(JSON.stringify({ error: String(error).slice(0, 2000) }), now, jobId);
    if (requestId) {
      db.prepare("UPDATE llm_requests SET status='failed', error=?, finished_at=? WHERE id=? AND status!='succeeded'").run(String(error).slice(0, 2000), now, requestId);
    }
  });
}

// ------------------------------------------------------------------
// Job updates
// ------------------------------------------------------------------

export function updateJobStatus(jobId, status, dbPath) {
  if (!JOB_STATUSES.has(status)) {
    throw new Error(`invalid status ${JSON.stringify(status)}; expected one of: ${[...JOB_STATUSES].sort().join(', ')}`);
  }
  const db = connect(dbPath);
  const now = nowIso();
  const existing = db.prepare("SELECT id FROM jobs WHERE id=?").get(jobId);
  if (!existing) throw new Error(`job not found: ${jobId}`);
  db.prepare("UPDATE jobs SET status=?, updated_at=? WHERE id=?").run(status, now, jobId);
  db.prepare("INSERT INTO events (id, job_id, event_type, note, occurred_at, created_at) VALUES (?, ?, 'status_changed', ?, ?, ?)").run(makeId('evt'), jobId, status, now, now);
}

export function updateJobStatuses(jobIds, status, dbPath) {
  if (!Array.isArray(jobIds) || jobIds.length === 0) {
    throw new Error('job_ids must be a non-empty array');
  }
  if (!JOB_STATUSES.has(status)) {
    throw new Error(`invalid status ${JSON.stringify(status)}; expected one of: ${[...JOB_STATUSES].sort().join(', ')}`);
  }
  const ids = [...new Set(jobIds.map(id => String(id || '').trim()).filter(Boolean))];
  if (ids.length === 0) throw new Error('job_ids must include at least one job id');

  const db = connect(dbPath);
  const now = nowIso();
  return withTransaction(db, () => {
    const update = db.prepare("UPDATE jobs SET status=?, updated_at=? WHERE id=?");
    const insertEvent = db.prepare("INSERT INTO events (id, job_id, event_type, note, occurred_at, created_at) VALUES (?, ?, 'status_changed', ?, ?, ?)");
    let updated = 0;
    for (const id of ids) {
      const result = update.run(status, now, id);
      if (result.changes > 0) {
        updated += result.changes;
        insertEvent.run(makeId('evt'), id, status, now, now);
      }
    }
    return { requested: ids.length, updated };
  });
}

export function markJobOpened(jobId, dbPath) {
  const db = connect(dbPath);
  const now = nowIso();
  return withTransaction(db, () => {
    const result = db.prepare("UPDATE jobs SET last_opened_at=?, updated_at=? WHERE id=?").run(now, now, jobId);
    if (result.changes === 0) throw new Error(`job not found: ${jobId}`);
    db.prepare("INSERT INTO events (id, job_id, event_type, note, occurred_at, created_at) VALUES (?, ?, 'source_opened', NULL, ?, ?)")
      .run(makeId('evt'), jobId, now, now);
    return { last_opened_at: now };
  });
}

export function markDataQualityReviewed(jobIds, note, dbPath) {
  if (!Array.isArray(jobIds) || jobIds.length === 0) {
    throw new Error('job_ids must be a non-empty array');
  }
  const ids = [...new Set(jobIds.map(id => String(id || '').trim()).filter(Boolean))];
  if (ids.length === 0) throw new Error('job_ids must include at least one job id');

  const db = connect(dbPath);
  const now = nowIso();
  const cleanNote = String(note || '').trim();
  return withTransaction(db, () => {
    const upsert = db.prepare("INSERT INTO data_quality_reviews (job_id, reviewed_at, note) VALUES (?, ?, ?) ON CONFLICT(job_id) DO UPDATE SET reviewed_at=excluded.reviewed_at, note=excluded.note");
    const insertEvent = db.prepare("INSERT INTO events (id, job_id, event_type, note, occurred_at, created_at) VALUES (?, ?, 'data_quality_reviewed', ?, ?, ?)");
    let updated = 0;
    for (const id of ids) {
      const exists = db.prepare("SELECT id FROM jobs WHERE id=?").get(id);
      if (!exists) continue;
      const result = upsert.run(id, now, cleanNote);
      if (result.changes > 0) {
        updated += 1;
        insertEvent.run(makeId('evt'), id, cleanNote, now, now);
      }
    }
    return { requested: ids.length, updated };
  });
}

export function clearDataQualityReviewed(jobIds, dbPath) {
  if (!Array.isArray(jobIds) || jobIds.length === 0) {
    throw new Error('job_ids must be a non-empty array');
  }
  const ids = [...new Set(jobIds.map(id => String(id || '').trim()).filter(Boolean))];
  if (ids.length === 0) throw new Error('job_ids must include at least one job id');
  const db = connect(dbPath);
  const placeholders = ids.map(() => '?').join(',');
  const result = db.prepare(`DELETE FROM data_quality_reviews WHERE job_id IN (${placeholders})`).run(...ids);
  return { requested: ids.length, updated: result.changes };
}

function hasMissingAiFields(row) {
  return !row.location
    || row.remote_type === 'unknown'
    || !(row.salary_min || row.salary_max || row.salary_note)
    || row.extraction_status === 'pending'
    || row.extraction_status === 'failed';
}

export function queueBulkLlmJobs(jobIds, mode, dbPath) {
  if (!Array.isArray(jobIds) || jobIds.length === 0) {
    throw new Error('job_ids must be a non-empty array');
  }
  if (!['extract', 'fit_score', 'missing_fields'].includes(mode)) {
    throw new Error("mode must be one of: extract, fit_score, missing_fields");
  }
  const ids = [...new Set(jobIds.map(id => String(id || '').trim()).filter(Boolean))];
  if (ids.length === 0) throw new Error('job_ids must include at least one job id');

  const db = connect(dbPath);
  const now = nowIso();
  return withTransaction(db, () => {
    const getJob = db.prepare("SELECT id, location, remote_type, salary_min, salary_max, salary_note, extraction_status FROM jobs WHERE id=?");
    const updateExtraction = db.prepare("UPDATE jobs SET extraction_status='pending', extraction_error=NULL, updated_at=? WHERE id=?");
    const insertEvent = db.prepare("INSERT INTO events (id, job_id, event_type, note, occurred_at, created_at) VALUES (?, ?, ?, ?, ?, ?)");
    let queued = 0;
    let skipped = 0;
    const requestIds = [];
    for (const id of ids) {
      const row = getJob.get(id);
      if (!row) {
        skipped++;
        continue;
      }
      if (mode === 'missing_fields' && !hasMissingAiFields(row)) {
        skipped++;
        continue;
      }
      if (mode === 'fit_score') {
        if (row.extraction_status !== 'succeeded') {
          skipped++;
          continue;
        }
        db.prepare("UPDATE jobs SET fit_status='pending', updated_at=? WHERE id=?").run(now, id);
        requestIds.push(upsertLlmRequest(db, id, 'fit_score', { resetAttempts: true }));
        insertEvent.run(makeId('evt'), id, 'fit_score_queued', 'bulk', now, now);
      } else {
        updateExtraction.run(now, id);
        requestIds.push(upsertLlmRequest(db, id, 'extract', { resetAttempts: true }));
        insertEvent.run(makeId('evt'), id, 'extraction_queued', mode === 'missing_fields' ? 'missing_fields' : 'bulk', now, now);
      }
      queued++;
    }
    return { requested: ids.length, queued, skipped, request_ids: requestIds };
  });
}

export function queueBulkLlmJobsByNumbers(jobNumbers, mode, dbPath) {
  if (!Array.isArray(jobNumbers) || jobNumbers.length === 0) {
    throw new Error('job_numbers must be a non-empty array');
  }
  const numbers = [...new Set(jobNumbers
    .map(n => String(n || '').trim().replace(/^#/, ''))
    .map(n => Number.parseInt(n, 10))
    .filter(Number.isInteger))];
  if (numbers.length === 0) throw new Error('job_numbers must include at least one job number');

  const db = connect(dbPath);
  const placeholders = numbers.map(() => '?').join(',');
  const rows = db.prepare(`SELECT id, job_number FROM jobs WHERE job_number IN (${placeholders})`).all(...numbers);
  const foundNumbers = new Set(rows.map(row => row.job_number));
  const result = rows.length
    ? queueBulkLlmJobs(rows.map(row => row.id), mode, dbPath)
    : { queued: 0, skipped: 0, request_ids: [] };
  return {
    ...result,
    requested: numbers.length,
    found: rows.length,
    job_numbers: rows.map(row => row.job_number),
    missing_job_numbers: numbers.filter(n => !foundNumbers.has(n)),
  };
}

export function addJobNote(jobId, note, dbPath) {
  note = (note || '').trim();
  if (!note) throw new Error('note cannot be empty');
  const db = connect(dbPath);
  const now = nowIso();
  const existing = db.prepare("SELECT id FROM jobs WHERE id=?").get(jobId);
  if (!existing) throw new Error(`job not found: ${jobId}`);
  db.prepare("INSERT INTO events (id, job_id, event_type, note, occurred_at, created_at) VALUES (?, ?, 'note_added', ?, ?, ?)").run(makeId('evt'), jobId, note, now, now);
}

export function updateJobFields(db, jobId, fields) {
  const allowed = new Set(['company', 'title', 'location', 'salary_min', 'salary_max', 'salary_note']);
  const toUpdate = {};
  for (const [k, v] of Object.entries(fields)) {
    if (allowed.has(k)) toUpdate[k] = v;
  }
  if (!Object.keys(toUpdate).length) return;
  const row = db.prepare("SELECT manual_overrides FROM jobs WHERE id=?").get(jobId);
  if (!row) throw new Error(`job not found: ${jobId}`);
  const existing = new Set(JSON.parse((row.manual_overrides) || '[]'));
  const newOverrides = JSON.stringify([...new Set([...existing, ...Object.keys(toUpdate)])].sort());
  toUpdate.manual_overrides = newOverrides;
  const setClause = Object.keys(toUpdate).map(k => `${k}=?`).join(', ');
  db.prepare(`UPDATE jobs SET ${setClause}, updated_at=strftime('%Y-%m-%dT%H:%M:%SZ','now') WHERE id=?`).run(...Object.values(toUpdate), jobId);
}

export function updateJobSkills(db, jobId, skills) {
  const row = db.prepare("SELECT extracted_json FROM jobs WHERE id=?").get(jobId);
  if (!row) return;
  let extracted = /** @type {any} */ ({});
  if (row.extracted_json) {
    try { extracted = JSON.parse(row.extracted_json); } catch { extracted = {}; }
  }
  extracted.skills = skills;
  db.prepare("UPDATE jobs SET extracted_json=?, updated_at=strftime('%Y-%m-%dT%H:%M:%SZ','now') WHERE id=?").run(JSON.stringify(extracted), jobId);
}

export function setJobRating(db, jobId, rating) {
  if (rating != null && (rating < 1 || rating > 5)) throw new Error(`Rating must be 1-5, got ${rating}`);
  db.prepare("UPDATE jobs SET rating=?, updated_at=strftime('%Y-%m-%dT%H:%M:%SZ','now') WHERE id=?").run(rating ?? null, jobId);
}

// ------------------------------------------------------------------
// Site reviews
// ------------------------------------------------------------------

export function insertSiteReview(review, dbPath) {
  const db = initDb(dbPath);
  const siteReviewId = makeId('site');
  const now = nowIso();
  const reviewedAt = review.reviewed_at instanceof Date
    ? review.reviewed_at.toISOString()
    : review.reviewed_at;

  let intervalDays;
  let nextIso;
  if (review.next_review_at) {
    const nextAt = review.next_review_at instanceof Date ? review.next_review_at : new Date(review.next_review_at);
    const reviewedDate = new Date(reviewedAt);
    intervalDays = Math.max(1, Math.floor((nextAt.getTime() - reviewedDate.getTime()) / (1000 * 60 * 60 * 24)));
    nextIso = nextAt.toISOString().replace(/\.\d{3}Z$/, 'Z');
  } else {
    const settings = getSettings(db);
    intervalDays = parseInt(settings.site_review_interval_days || '14');
    const nextDate = new Date(new Date(reviewedAt).getTime() + intervalDays * 86400000);
    nextIso = nextDate.toISOString().replace(/\.\d{3}Z$/, 'Z');
  }

  const reviewedIso = new Date(reviewedAt).toISOString().replace(/\.\d{3}Z$/, 'Z');

  db.prepare(`INSERT INTO site_reviews (id, site_url, site_origin, page_title, reviewed_at, next_review_at, note, created_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?)`).run(
    siteReviewId, review.site_url, review.site_origin, review.page_title || null,
    reviewedIso, nextIso, review.note || null, now
  );

  db.prepare(`INSERT INTO sites (origin, url, company_name, company_website, jobs_url, company_description, page_title, interval_days, last_reviewed_at, next_review_at, note, state)
    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    ON CONFLICT(origin) DO UPDATE SET
      url=excluded.url,
      page_title=COALESCE(NULLIF(excluded.page_title,''),page_title),
      last_reviewed_at=excluded.last_reviewed_at,
      next_review_at=excluded.next_review_at,
      interval_days=excluded.interval_days,
      company_name=COALESCE(NULLIF(excluded.company_name,''),company_name),
      company_website=COALESCE(NULLIF(excluded.company_website,''),company_website),
      jobs_url=COALESCE(NULLIF(excluded.jobs_url,''),jobs_url),
      company_description=COALESCE(NULLIF(excluded.company_description,''),company_description),
      state=excluded.state,
      updated_at=strftime('%Y-%m-%dT%H:%M:%SZ','now')`).run(
    review.site_origin, review.site_url,
    inferSiteCompanyName(review.site_origin, review.page_title),
    inferCompanyWebsite(review.site_origin, review.site_url),
    review.site_url, '', review.page_title || '', intervalDays,
    reviewedIso, nextIso, review.note || '', 'reviewed'
  );

  return siteReviewId;
}

// ------------------------------------------------------------------
// Sites
// ------------------------------------------------------------------

export function getSites(db) {
  return db.prepare("SELECT * FROM sites ORDER BY next_review_at ASC NULLS LAST, origin ASC").all();
}

export function addSite(db, { origin, url, pageTitle = '', intervalDays = 14, note = '', state = 'not_reviewed', companyName, companyWebsite, jobsUrl, companyDescription, addedAt }) {
  const now = new Date();
  const nowIso2 = now.toISOString().replace(/\.\d{3}Z$/, 'Z');
  const nextIso = new Date(now.getTime() + intervalDays * 86400000).toISOString().replace(/\.\d{3}Z$/, 'Z');
  const normalizedState = normalizeSiteState(state);
  const resolvedCompanyName = companyName ?? inferSiteCompanyName(origin, pageTitle);
  const resolvedCompanyWebsite = companyWebsite ?? inferCompanyWebsite(origin, url);
  const resolvedJobsUrl = jobsUrl || url;
  const resolvedCompanyDescription = (companyDescription || '').trim();
  const resolvedAddedAt = addedAt || nowIso2;

  db.prepare(`INSERT INTO sites (origin, url, page_title, interval_days, last_reviewed_at, next_review_at, note, state, company_name, company_website, jobs_url, company_description, added_at)
    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    ON CONFLICT(origin) DO UPDATE SET
      url=excluded.url, page_title=excluded.page_title, interval_days=excluded.interval_days, note=excluded.note,
      state=CASE WHEN state IS NULL OR TRIM(state)='' THEN excluded.state ELSE state END,
      company_name=COALESCE(NULLIF(excluded.company_name,''),company_name),
      company_website=COALESCE(NULLIF(excluded.company_website,''),company_website),
      jobs_url=COALESCE(NULLIF(excluded.jobs_url,''),jobs_url),
      company_description=COALESCE(NULLIF(excluded.company_description,''),company_description),
      added_at=COALESCE(sites.added_at,excluded.added_at),
      updated_at=strftime('%Y-%m-%dT%H:%M:%SZ','now')`).run(
    origin, url, pageTitle, intervalDays, null, nextIso, note, normalizedState,
    resolvedCompanyName, resolvedCompanyWebsite, resolvedJobsUrl, resolvedCompanyDescription, resolvedAddedAt
  );
  return db.prepare("SELECT * FROM sites WHERE origin=?").get(origin);
}

export function markSiteReviewed(db, siteId, intervalDays) {
  if (intervalDays == null) {
    const row = db.prepare("SELECT interval_days FROM sites WHERE id=?").get(siteId);
    intervalDays = row?.interval_days ?? 14;
  }
  db.prepare("UPDATE sites SET interval_days=COALESCE(?,interval_days) WHERE id=?").run(intervalDays, siteId);
  return setSiteState(db, siteId, 'reviewed');
}

export function setSiteNextReview(db, siteId, days) {
  const now = new Date();
  const nextIso = new Date(now.getTime() + days * 86400000).toISOString().replace(/\.\d{3}Z$/, 'Z');
  const nowIso2 = now.toISOString().replace(/\.\d{3}Z$/, 'Z');
  db.prepare("UPDATE sites SET next_review_at=?, interval_days=?, updated_at=? WHERE id=?").run(nextIso, days, nowIso2, siteId);
  return db.prepare("SELECT * FROM sites WHERE id=?").get(siteId);
}

export function setSiteState(db, siteId, state) {
  const normalized = normalizeSiteState(state);
  const now = new Date();
  const nowIso2 = now.toISOString().replace(/\.\d{3}Z$/, 'Z');

  if (normalized === 'exclude' || normalized === 'not_reviewed') {
    db.prepare("UPDATE sites SET state=?, last_reviewed_at=NULL, next_review_at=NULL, updated_at=? WHERE id=?").run(normalized, nowIso2, siteId);
    return db.prepare("SELECT * FROM sites WHERE id=?").get(siteId);
  }

  const row = db.prepare("SELECT interval_days FROM sites WHERE id=?").get(siteId);
  const days = row?.interval_days ?? 14;
  const nextIso = new Date(now.getTime() + days * 86400000).toISOString().replace(/\.\d{3}Z$/, 'Z');
  db.prepare("UPDATE sites SET state=?, last_reviewed_at=?, next_review_at=?, updated_at=? WHERE id=?").run(normalized, nowIso2, nextIso, nowIso2, siteId);
  return db.prepare("SELECT * FROM sites WHERE id=?").get(siteId);
}

export function setSiteStateForOrigin(db, origin, state, intervalDays = 14) {
  const row = db.prepare("SELECT id, interval_days FROM sites WHERE origin=?").get(origin);
  if (!row) throw new Error(`site not found: ${origin}`);
  if (row.id) return setSiteState(db, row.id, state);
  const normalized = normalizeSiteState(state);
  const now = new Date();
  const nowIso2 = now.toISOString().replace(/\.\d{3}Z$/, 'Z');
  const days = parseInt(intervalDays || row.interval_days || 14);
  if (normalized === 'exclude' || normalized === 'not_reviewed') {
    db.prepare("UPDATE sites SET state=?, last_reviewed_at=NULL, next_review_at=NULL, updated_at=? WHERE origin=?").run(normalized, nowIso2, origin);
  } else {
    const nextIso = new Date(now.getTime() + days * 86400000).toISOString().replace(/\.\d{3}Z$/, 'Z');
    db.prepare("UPDATE sites SET state=?, last_reviewed_at=?, next_review_at=?, interval_days=?, updated_at=? WHERE origin=?").run(normalized, nowIso2, nextIso, days, nowIso2, origin);
  }
  return db.prepare("SELECT * FROM sites WHERE origin=?").get(origin);
}

export function updateSiteNote(db, siteId, note) {
  db.prepare("UPDATE sites SET note=?, updated_at=strftime('%Y-%m-%dT%H:%M:%SZ','now') WHERE id=?").run(note, siteId);
  return db.prepare("SELECT * FROM sites WHERE id=?").get(siteId);
}

export function deleteSite(db, siteId) {
  db.prepare("DELETE FROM sites WHERE id=?").run(siteId);
}

export function getSitesDueCount(db) {
  const today = new Date().toISOString();
  const row = db.prepare("SELECT COUNT(*) AS n FROM sites WHERE state!='exclude' AND (next_review_at IS NULL OR next_review_at<=?)").get(today);
  return row ? Number(row.n) : 0;
}

export function resolveSite(db, siteRef) {
  const decoded = decodeURIComponent(siteRef);
  let row = db.prepare("SELECT id, origin FROM sites WHERE id=?").get(decoded);
  if (!row) row = db.prepare("SELECT id, origin FROM sites WHERE origin=?").get(decoded);
  return row || null;
}

export function reviewSiteRow(db, row) {
  if (!row.id) return setSiteStateForOrigin(db, row.origin, 'reviewed');
  return markSiteReviewed(db, row.id);
}

// ------------------------------------------------------------------
// Duplicate decisions
// ------------------------------------------------------------------

export function detectDomainDuplicateJobs(dbPath) {
  const db = initDb(dbPath);
  const rows = db.prepare(`SELECT jobs.id, jobs.status, jobs.company, jobs.title,
      jobs.duplicate_of_job_id, jobs.duplicate_confidence, jobs.application_url,
      jobs.location, jobs.remote_type, jobs.salary_min, jobs.salary_max, jobs.salary_currency,
      jobs.employment_type, jobs.seniority,
      captures.cleaned_description,
      COALESCE(captures.canonical_url, captures.url) AS source_url
    FROM jobs JOIN captures ON captures.id=jobs.capture_id
    WHERE jobs.extraction_status='succeeded'
      AND jobs.company IS NOT NULL AND TRIM(jobs.company) != ''
      AND jobs.title IS NOT NULL AND TRIM(jobs.title) != ''
      AND jobs.status NOT IN ('archived', 'not_available')`).all();

  const groups = new Map();
  for (const row of rows) {
    const companyKey = normalizeDuplicateText(row.company);
    const titleKey = normalizeDuplicateText(row.title);
    if (!companyKey || !titleKey) continue;
    const key = `${companyKey}\n${titleKey}`;
    if (!groups.has(key)) groups.set(key, []);
    groups.get(key).push({
      ...row,
      source_domain_score: companyDomainScore(row.company, row.source_url),
      source_hostname: sourceHostname(row.source_url),
    });
  }

  const now = nowIso();
  let groupsDetected = 0;
  let jobsMarked = 0;

  return withTransaction(db, () => {
    for (const group of groups.values()) {
      if (group.length < 2) continue;
      const hostnames = new Set(group.map(row => row.source_hostname).filter(Boolean));
      if (hostnames.size < 2) continue;

      const sorted = [...group].sort((a, b) => {
        if (b.source_domain_score !== a.source_domain_score) return b.source_domain_score - a.source_domain_score;
        return String(a.id).localeCompare(String(b.id));
      });
      const keep = sorted[0];
      const runnerUpScore = sorted[1]?.source_domain_score ?? 0;
      if (keep.source_domain_score <= 0 || keep.source_domain_score === runnerUpScore) continue;

      let groupMarked = 0;
      for (const job of sorted.slice(1)) {
        if (job.status !== 'saved' && job.status !== 'duplicate') continue;
        const evidence = duplicateEvidenceMatch(keep, job);
        if (!evidence) continue;

        const domainConfidence = 0.65 + ((keep.source_domain_score - job.source_domain_score) / 100) * 0.24;
        const descriptionConfidence = evidence.descriptionSimilarity == null
          ? 0
          : Math.max(0, evidence.descriptionSimilarity - 0.5) * 0.2;
        const confidence = Math.min(0.99, domainConfidence + descriptionConfidence);
        const result = db.prepare(`UPDATE jobs
          SET duplicate_of_job_id=?, duplicate_confidence=?, updated_at=?
          WHERE id=? AND (duplicate_of_job_id IS NOT ? OR duplicate_confidence IS NOT ?)`)
          .run(keep.id, confidence, now, job.id, keep.id, confidence);
        if (result.changes > 0) {
          jobsMarked += 1;
          groupMarked += 1;
          db.prepare(`INSERT INTO events (id, job_id, event_type, note, occurred_at, created_at)
            VALUES (?, ?, 'duplicate_detected', ?, ?, ?)`)
            .run(makeId('evt'), job.id, duplicateDetectionNote(keep, job, evidence), now, now);
        }
      }

      const keepResult = db.prepare(`UPDATE jobs
        SET duplicate_of_job_id=NULL, duplicate_confidence=NULL,
          status=CASE WHEN status='duplicate' THEN 'saved' ELSE status END,
          updated_at=?
        WHERE id=? AND (duplicate_of_job_id IS NOT NULL OR duplicate_confidence IS NOT NULL OR status='duplicate')`)
        .run(now, keep.id);
      if (keepResult.changes > 0) {
        db.prepare(`INSERT INTO events (id, job_id, event_type, note, occurred_at, created_at)
          VALUES (?, ?, 'duplicate_preferred', ?, ?, ?)`)
          .run(makeId('evt'), keep.id, `preferred source ${keep.source_hostname}`, now, now);
      }

      if (groupMarked > 0 || keepResult.changes > 0) groupsDetected += 1;
    }
    return { groups_detected: groupsDetected, jobs_marked: jobsMarked };
  });
}

export function decideDuplicateLinks(jobIds, decision, keepJobId, note, dbPath) {
  if (decision !== 'merged' && decision !== 'not_duplicate') {
    throw new Error("decision must be 'merged' or 'not_duplicate'");
  }
  if (!Array.isArray(jobIds) || jobIds.length < 2) {
    throw new Error('job_ids must include at least two job ids');
  }
  const ids = [...new Set(jobIds.map(id => String(id || '').trim()).filter(Boolean))];
  if (ids.length < 2) throw new Error('job_ids must include at least two job ids');

  const db = connect(dbPath);
  const now = nowIso();

  return withTransaction(db, () => {
    const placeholders = ids.map(() => '?').join(',');
    const existing = db.prepare(`SELECT id FROM jobs WHERE id IN (${placeholders})`).all(...ids).map(row => row.id);
    if (existing.length !== ids.length) throw new Error('one or more duplicate jobs were not found');

    if (decision === 'merged') {
      keepJobId = keepJobId || ids[0];
      if (!ids.includes(keepJobId)) throw new Error(`keep_job_id is not in duplicate group: ${keepJobId}`);
      for (const jid of ids) {
        if (jid === keepJobId) continue;
        db.prepare("UPDATE jobs SET status='duplicate', duplicate_of_job_id=?, duplicate_confidence=COALESCE(duplicate_confidence, 1.0), updated_at=? WHERE id=?")
          .run(keepJobId, now, jid);
      }
      db.prepare("UPDATE jobs SET duplicate_of_job_id=NULL, duplicate_confidence=NULL, status=CASE WHEN status='duplicate' THEN 'saved' ELSE status END, updated_at=? WHERE id=?")
        .run(now, keepJobId);
    } else {
      keepJobId = null;
      db.prepare(`UPDATE jobs SET duplicate_of_job_id=NULL, duplicate_confidence=NULL,
        status=CASE WHEN status='duplicate' THEN 'saved' ELSE status END,
        updated_at=? WHERE id IN (${placeholders})`).run(now, ...ids);
    }

    for (const jid of ids) {
      db.prepare("INSERT INTO events (id, job_id, event_type, note, occurred_at, created_at) VALUES (?, ?, 'duplicate_decided', ?, ?, ?)")
        .run(makeId('evt'), jid, `${decision}${note ? `: ${String(note).trim()}` : ''}`, now, now);
    }
  });
}

export function decideDuplicateGroup(cleanedHash, decision, keepJobId, note, dbPath) {
  if (decision !== 'merged' && decision !== 'not_duplicate') {
    throw new Error("decision must be 'merged' or 'not_duplicate'");
  }
  const db = connect(dbPath);
  const now = nowIso();

  return withTransaction(db, () => {
    const rows = db.prepare(`SELECT jobs.id FROM jobs JOIN captures ON captures.id=jobs.capture_id
      WHERE captures.cleaned_hash=? ORDER BY captures.created_at`).all(cleanedHash);
    const jobIds = rows.map(r => r.id);
    if (jobIds.length < 2) throw new Error(`duplicate group not found: ${cleanedHash}`);

    if (decision === 'merged') {
      keepJobId = keepJobId || jobIds[0];
      if (!jobIds.includes(keepJobId)) throw new Error(`keep_job_id is not in duplicate group: ${keepJobId}`);
      for (const jid of jobIds) {
        if (jid === keepJobId) continue;
        db.prepare("UPDATE jobs SET status='duplicate', duplicate_of_job_id=?, duplicate_confidence=1.0, updated_at=? WHERE id=?").run(keepJobId, now, jid);
      }
    } else {
      keepJobId = null;
      const placeholders = jobIds.map(() => '?').join(',');
      db.prepare(`UPDATE jobs SET duplicate_of_job_id=NULL, duplicate_confidence=NULL,
        status=CASE WHEN status='duplicate' THEN 'saved' ELSE status END,
        updated_at=? WHERE id IN (${placeholders})`).run(now, ...jobIds);
    }

    db.prepare(`INSERT OR REPLACE INTO duplicate_decisions (cleaned_hash, decision, keep_job_id, note, decided_at, created_at) VALUES (?, ?, ?, ?, ?, ?)`).run(cleanedHash, decision, keepJobId, (note || '').trim(), now, now);
    for (const jid of jobIds) {
      db.prepare("INSERT INTO events (id, job_id, event_type, note, occurred_at, created_at) VALUES (?, ?, 'duplicate_decided', ?, ?, ?)").run(makeId('evt'), jid, decision, now, now);
    }
  });
}

// ------------------------------------------------------------------
// Actions
// ------------------------------------------------------------------

export function createNextAction(db, jobId, note, dueDate) {
  db.prepare("UPDATE job_actions SET completed_at=strftime('%Y-%m-%dT%H:%M:%SZ','now'), updated_at=strftime('%Y-%m-%dT%H:%M:%SZ','now') WHERE job_id=? AND completed_at IS NULL").run(jobId);
  db.prepare("INSERT INTO job_actions (job_id, note, due_date) VALUES (?, ?, ?)").run(jobId, note, dueDate);
  return db.prepare("SELECT * FROM job_actions WHERE job_id=? AND completed_at IS NULL ORDER BY created_at DESC LIMIT 1").get(jobId);
}

export function getActiveAction(db, jobId) {
  return db.prepare("SELECT * FROM job_actions WHERE job_id=? AND completed_at IS NULL ORDER BY created_at DESC LIMIT 1").get(jobId) || null;
}

export function completeAction(db, actionId) {
  const result = db.prepare("UPDATE job_actions SET completed_at=strftime('%Y-%m-%dT%H:%M:%SZ','now'), updated_at=strftime('%Y-%m-%dT%H:%M:%SZ','now') WHERE id=?").run(actionId);
  if (result.changes === 0) throw new Error(`action not found: ${actionId}`);
}

export function snoozeAction(db, actionId, days) {
  const newDue = new Date(Date.now() + days * 86400000).toISOString().slice(0, 10);
  const result = db.prepare("UPDATE job_actions SET due_date=?, snoozed_until=?, updated_at=strftime('%Y-%m-%dT%H:%M:%SZ','now') WHERE id=?").run(newDue, newDue, actionId);
  if (result.changes === 0) throw new Error(`action not found: ${actionId}`);
  return db.prepare("SELECT * FROM job_actions WHERE id=?").get(actionId);
}

export function getNeedsActionCount(db) {
  const today = new Date().toISOString().slice(0, 10);
  const row = db.prepare("SELECT COUNT(DISTINCT job_id) AS n FROM job_actions WHERE completed_at IS NULL AND due_date<=?").get(today);
  return row ? Number(row.n) : 0;
}

// ------------------------------------------------------------------
// Dashboard queries
// ------------------------------------------------------------------

export function listDashboardJobs(dbPath, limit = 50) {
  const db = initDb(dbPath);
  return db.prepare(`SELECT jobs.id AS job_id, jobs.job_number, captures.id AS capture_id,
    jobs.status, jobs.extraction_status, jobs.company, jobs.title, jobs.location, jobs.remote_type,
    jobs.salary_min, jobs.salary_max, jobs.salary_currency, jobs.salary_note, jobs.rating,
    jobs.extraction_model, jobs.application_url, jobs.extraction_confidence,
    captures.page_title, COALESCE(captures.canonical_url, captures.url) AS source_url,
    captures.captured_at, jobs.extracted_at
    FROM jobs JOIN captures ON captures.id=jobs.capture_id
    ORDER BY captures.created_at DESC LIMIT ?`).all(limit);
}
