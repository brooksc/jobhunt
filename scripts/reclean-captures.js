#!/usr/bin/env node
// Re-run cleanDescription() against all stored captures and re-queue LLM extraction
// where the cleaned output has changed (e.g. after a cleaning.js refactor).
//
// Usage: node scripts/reclean-captures.js [--db-path /path/to/jobhunt.db] [--dry-run]

import { createHash } from 'node:crypto';
import { parseArgs } from 'node:util';
import { DatabaseSync } from 'node:sqlite';
import { cleanDescription } from '../server/cleaning.js';
import { defaultDbPath } from '../server/db.js';

const { values: args } = parseArgs({
  options: {
    'db-path': { type: 'string' },
    'dry-run': { type: 'boolean', default: false },
  },
  strict: false,
});

const dbPath = args['db-path'] || defaultDbPath();
const dryRun = args['dry-run'];

console.log(`Database: ${dbPath}`);
if (dryRun) console.log('DRY RUN — no changes will be written');

const db = new DatabaseSync(dbPath);

const now = new Date().toISOString();
let checked = 0, changed = 0, queued = 0;

const captures = db.prepare(`
  SELECT c.id, c.visible_text, c.selected_text, c.structured_data_json,
         c.cleaned_description, j.id AS job_id, j.status
  FROM captures c
  JOIN jobs j ON j.capture_id = c.id
  WHERE j.status NOT IN ('archived')
  ORDER BY c.created_at DESC
`).all();

const updateCleaned = db.prepare(
  `UPDATE captures SET cleaned_description=?, cleaned_hash=? WHERE id=?`
);
const resetExtraction = db.prepare(
  `UPDATE jobs SET extraction_status='pending', extraction_error=NULL, updated_at=? WHERE id=?`
);
const upsertRequest = db.prepare(`
  INSERT INTO llm_requests (id, job_id, request_type, status, attempt, created_at)
  VALUES (?, ?, 'extract', 'queued', 1, ?)
  ON CONFLICT(job_id, request_type) DO UPDATE SET
    status='queued', attempt=1, error=NULL, started_at=NULL, finished_at=NULL
`);

function makeId(prefix) {
  return `${prefix}_${Math.random().toString(36).slice(2, 10)}${Math.random().toString(36).slice(2, 10)}`;
}

function hashText(text) {
  return createHash('sha256').update(text, 'utf8').digest('hex');
}

const beginStmt = db.prepare('BEGIN');
const commitStmt = db.prepare('COMMIT');
function updateInTransaction(captureId, jobId, newCleaned) {
  beginStmt.run();
  updateCleaned.run(newCleaned, hashText(newCleaned), captureId);
  resetExtraction.run(now, jobId);
  upsertRequest.run(makeId('req'), jobId, now);
  commitStmt.run();
}

for (const row of captures) {
  checked++;
  let structuredData = [];
  try {
    structuredData = JSON.parse(row.structured_data_json || '[]');
  } catch { /* ignore parse errors */ }

  const newCleaned = cleanDescription({
    selectedText: row.selected_text || '',
    visibleText: row.visible_text || '',
    structuredData,
  });

  const oldCleaned = row.cleaned_description || '';
  if (newCleaned === oldCleaned) continue;

  changed++;
  console.log(`  [${row.job_id}] status=${row.status} — cleaned_description changed (${oldCleaned.length} → ${newCleaned.length} chars)`);

  if (!dryRun) {
    updateInTransaction(row.id, row.job_id, newCleaned);
    queued++;
  }
}

console.log(`\nChecked ${checked} captures. ${changed} changed.`);
if (!dryRun) {
  console.log(`${queued} re-queued for extraction.`);
} else {
  console.log(`(dry run — run without --dry-run to apply)`);
}
