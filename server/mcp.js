#!/usr/bin/env node
// MCP stdio entry point for Claude Code and Codex.

import { Server } from '@modelcontextprotocol/sdk/server/index.js';
import { StdioServerTransport } from '@modelcontextprotocol/sdk/server/stdio.js';
import { CallToolRequestSchema, ListToolsRequestSchema } from '@modelcontextprotocol/sdk/types.js';
import {
  addJobNote,
  addSite as addSiteRow,
  deleteSite,
  getSettings,
  getSites,
  getSitesDueCount,
  initDb,
  insertCapture,
  resetJobExtraction,
  setSiteNextReview,
  setSiteState,
  updateJobFields,
  updateJobStatus,
} from './db.js';

let defaultDbPath = null;

function parseArgs(argv) {
  for (let i = 0; i < argv.length; i++) {
    if (argv[i] === '--db-path') {
      defaultDbPath = argv[i + 1] || null;
      i++;
    }
  }
}

function activeDbPath(dbPath) {
  return dbPath || defaultDbPath || undefined;
}

function parseJson(value) {
  if (!value) return null;
  try {
    return JSON.parse(value);
  } catch {
    return null;
  }
}

function normalizeSiteOrigin(url) {
  try {
    const parsed = new URL(url);
    return `${parsed.protocol}//${parsed.host}`;
  } catch {
    return url;
  }
}

function rowToObject(row) {
  return row ? { ...row } : {};
}

function textResult(value) {
  return {
    content: [
      {
        type: 'text',
        text: JSON.stringify(value, null, 2),
      },
    ],
  };
}

function requirePositiveLimit(limit) {
  const resolved = Number(limit ?? 50);
  if (!Number.isInteger(resolved) || resolved <= 0) throw new Error('limit must be greater than 0');
  return resolved;
}

const optionalDbPath = {
  db_path: { type: 'string', description: 'Override the configured Jobhunt SQLite database path.' },
};

const tools = [
  {
    name: 'jobs_list',
    description: 'List jobs with extraction metadata and text hashes.',
    inputSchema: {
      type: 'object',
      properties: {
        limit: { type: 'integer', default: 50, minimum: 1 },
        status: { type: 'string' },
        ...optionalDbPath,
      },
    },
  },
  {
    name: 'job_get',
    description: 'Fetch full job metadata, capture text, and events.',
    inputSchema: {
      type: 'object',
      required: ['job_id'],
      properties: {
        job_id: { type: 'string' },
        ...optionalDbPath,
      },
    },
  },
  {
    name: 'add_capture',
    description: 'Create or update a capture; returns duplicate status and capture id.',
    inputSchema: {
      type: 'object',
      required: ['url', 'page_title'],
      properties: {
        url: { type: 'string' },
        page_title: { type: 'string' },
        visible_text: { type: 'string', default: '' },
        selected_text: { type: 'string', default: '' },
        canonical_url: { type: 'string' },
        captured_at: { type: 'string' },
        schema_version: { type: 'integer', default: 1 },
        structured_data: { type: 'array', default: [] },
        user_note: { type: 'string', default: '' },
        source_browser: { type: 'string' },
        source_extension_version: { type: 'string' },
        ...optionalDbPath,
      },
    },
  },
  {
    name: 'update_job',
    description: 'Patch selected job fields.',
    inputSchema: {
      type: 'object',
      required: ['job_id'],
      properties: {
        job_id: { type: 'string' },
        company: { type: 'string' },
        title: { type: 'string' },
        location: { type: 'string' },
        salary_min: { type: 'integer' },
        salary_max: { type: 'integer' },
        salary_note: { type: 'string' },
        ...optionalDbPath,
      },
    },
  },
  {
    name: 'set_job_status',
    description: 'Set workflow status.',
    inputSchema: {
      type: 'object',
      required: ['job_id', 'status'],
      properties: {
        job_id: { type: 'string' },
        status: { type: 'string' },
        ...optionalDbPath,
      },
    },
  },
  {
    name: 'add_job_note',
    description: 'Add a note event to a job.',
    inputSchema: {
      type: 'object',
      required: ['job_id', 'note'],
      properties: {
        job_id: { type: 'string' },
        note: { type: 'string' },
        ...optionalDbPath,
      },
    },
  },
  {
    name: 'rerun_extraction',
    description: 'Reset extraction so it will be retried on the next extraction run.',
    inputSchema: {
      type: 'object',
      required: ['job_id'],
      properties: {
        job_id: { type: 'string' },
        ...optionalDbPath,
      },
    },
  },
  {
    name: 'list_sites',
    description: 'List all prospecting/review sites.',
    inputSchema: {
      type: 'object',
      properties: optionalDbPath,
    },
  },
  {
    name: 'add_site',
    description: 'Create or update a prospective site for later review.',
    inputSchema: {
      type: 'object',
      required: ['url'],
      properties: {
        url: { type: 'string' },
        origin: { type: 'string' },
        page_title: { type: 'string', default: '' },
        interval_days: { type: 'integer', default: 14 },
        note: { type: 'string', default: '' },
        state: { type: 'string', default: 'not_reviewed' },
        company_name: { type: 'string' },
        company_website: { type: 'string' },
        jobs_url: { type: 'string' },
        company_description: { type: 'string' },
        added_at: { type: 'string' },
        ...optionalDbPath,
      },
    },
  },
  {
    name: 'update_site',
    description: 'Update site metadata or next-review schedule.',
    inputSchema: {
      type: 'object',
      required: ['site_id'],
      properties: {
        site_id: { type: 'string' },
        note: { type: 'string' },
        interval_days: { type: 'integer' },
        next_review_days: { type: 'integer' },
        state: { type: 'string' },
        company_name: { type: 'string' },
        company_website: { type: 'string' },
        jobs_url: { type: 'string' },
        company_description: { type: 'string' },
        ...optionalDbPath,
      },
    },
  },
  {
    name: 'delete_site',
    description: 'Delete a prospect site.',
    inputSchema: {
      type: 'object',
      required: ['site_id'],
      properties: {
        site_id: { type: 'string' },
        ...optionalDbPath,
      },
    },
  },
  {
    name: 'workflow_snapshot',
    description: 'Compact status snapshot for triage workflows.',
    inputSchema: {
      type: 'object',
      properties: optionalDbPath,
    },
  },
];

function jobsList(args) {
  const limit = requirePositiveLimit(args.limit);
  const dbPath = activeDbPath(args.db_path);
  const db = initDb(dbPath);
  const params = [];
  let whereClause = '';
  if (args.status) {
    whereClause = 'WHERE jobs.status = ?';
    params.push(args.status);
  }
  const rows = db.prepare(`
    SELECT
      jobs.id AS job_id,
      jobs.job_number,
      jobs.status,
      jobs.extraction_status,
      jobs.company,
      jobs.title,
      jobs.location,
      jobs.remote_type,
      jobs.salary_min,
      jobs.salary_max,
      jobs.salary_currency,
      jobs.salary_note,
      jobs.rating,
      jobs.extracted_at,
      jobs.created_at,
      jobs.updated_at,
      jobs.extraction_model,
      jobs.application_url,
      jobs.extraction_confidence,
      captures.cleaned_description,
      captures.raw_hash,
      captures.cleaned_hash,
      captures.page_title,
      COALESCE(captures.canonical_url, captures.url) AS source_url,
      captures.captured_at,
      COALESCE(NULLIF(captures.selected_text, ''), captures.visible_text) AS raw_text,
      jobs.extracted_json
    FROM jobs
    JOIN captures ON captures.id = jobs.capture_id
    ${whereClause}
    ORDER BY captures.captured_at DESC
    LIMIT ?
  `).all(...params, limit);

  return rows.map(row => ({
    job_id: row.job_id,
    job_number: row.job_number,
    status: row.status,
    extraction_status: row.extraction_status,
    company: row.company,
    title: row.title,
    location: row.location,
    remote_type: row.remote_type,
    salary_min: row.salary_min,
    salary_max: row.salary_max,
    salary_currency: row.salary_currency,
    salary_note: row.salary_note,
    rating: row.rating,
    extracted_at: row.extracted_at,
    created_at: row.created_at,
    updated_at: row.updated_at,
    source_url: row.source_url,
    page_title: row.page_title,
    captured_at: row.captured_at,
    raw_hash: row.raw_hash,
    cleaned_hash: row.cleaned_hash,
    raw_text: row.raw_text || '',
    cleaned_description: row.cleaned_description,
    extracted_json: parseJson(row.extracted_json),
    metadata: {
      extraction_model: row.extraction_model,
      application_url: row.application_url,
      extraction_confidence: row.extraction_confidence,
    },
  }));
}

function jobGet(args) {
  const db = initDb(activeDbPath(args.db_path));
  const row = db.prepare(`
    SELECT
      jobs.id AS job_id,
      jobs.job_number,
      jobs.status,
      jobs.extraction_status,
      jobs.extraction_error,
      jobs.company,
      jobs.title,
      jobs.location,
      jobs.remote_type,
      jobs.salary_min,
      jobs.salary_max,
      jobs.salary_currency,
      jobs.salary_note,
      jobs.employment_type,
      jobs.seniority,
      jobs.rating,
      jobs.duplicate_of_job_id,
      jobs.extraction_model,
      jobs.application_url,
      jobs.extraction_confidence,
      jobs.extracted_at,
      jobs.created_at,
      jobs.updated_at,
      captures.cleaned_description,
      captures.raw_hash,
      captures.cleaned_hash,
      captures.selected_text,
      captures.visible_text,
      captures.structured_data_json,
      captures.page_title,
      COALESCE(captures.canonical_url, captures.url) AS source_url,
      captures.captured_at,
      jobs.extracted_json
    FROM jobs
    JOIN captures ON captures.id = jobs.capture_id
    WHERE jobs.id = ?
  `).get(args.job_id);
  if (!row) throw new Error(`job not found: ${args.job_id}`);

  const events = db.prepare(`
    SELECT event_type, note, occurred_at
    FROM events
    WHERE job_id = ?
    ORDER BY occurred_at DESC
  `).all(args.job_id);

  return {
    job: {
      job_id: row.job_id,
      job_number: row.job_number,
      status: row.status,
      extraction_status: row.extraction_status,
      extraction_error: row.extraction_error,
      company: row.company,
      title: row.title,
      location: row.location,
      remote_type: row.remote_type,
      employment_type: row.employment_type,
      seniority: row.seniority,
      salary_min: row.salary_min,
      salary_max: row.salary_max,
      salary_currency: row.salary_currency,
      salary_note: row.salary_note,
      rating: row.rating,
      duplicate_of_job_id: row.duplicate_of_job_id,
      extracted_at: row.extracted_at,
      created_at: row.created_at,
      updated_at: row.updated_at,
      extraction_model: row.extraction_model,
      application_url: row.application_url,
      extraction_confidence: row.extraction_confidence,
      raw_hash: row.raw_hash,
      cleaned_hash: row.cleaned_hash,
      page_title: row.page_title,
      source_url: row.source_url,
      captured_at: row.captured_at,
      cleaned_description: row.cleaned_description,
      captured_text: {
        selected_text: row.selected_text || '',
        visible_text: row.visible_text || '',
        structured_data: parseJson(row.structured_data_json) || [],
      },
      extracted_json: parseJson(row.extracted_json),
    },
    events,
  };
}

function addCapture(args) {
  if (!args.visible_text && !args.selected_text) {
    throw new Error('selected_text or visible_text is required');
  }
  const result = insertCapture({
    schema_version: args.schema_version || 1,
    captured_at: args.captured_at ? new Date(args.captured_at) : new Date(),
    url: args.url,
    canonical_url: args.canonical_url || null,
    page_title: args.page_title,
    selected_text: args.selected_text || '',
    visible_text: args.visible_text || '',
    structured_data: args.structured_data || [],
    user_note: args.user_note || '',
    source: {
      browser: args.source_browser || null,
      extension_version: args.source_extension_version || null,
    },
  }, activeDbPath(args.db_path));
  return { ok: true, capture_id: result.capture_id, duplicate: result.duplicate, duplicate_of_job_id: result.duplicate_of_job_id };
}

function updateJob(args) {
  const fields = {
    company: args.company,
    title: args.title,
    location: args.location,
    salary_min: args.salary_min,
    salary_max: args.salary_max,
    salary_note: args.salary_note,
  };
  if (Object.values(fields).every(value => value == null)) throw new Error('at least one field must be provided');
  const db = initDb(activeDbPath(args.db_path));
  updateJobFields(db, args.job_id, fields);
  return { ok: true, job_id: args.job_id };
}

function addSite(args) {
  const db = initDb(activeDbPath(args.db_path));
  const origin = args.origin?.trim() || normalizeSiteOrigin(args.url);
  if (!origin) throw new Error('origin or URL is required');
  return rowToObject(addSiteRow(db, {
    origin,
    url: args.url,
    pageTitle: args.page_title || '',
    intervalDays: args.interval_days || 14,
    note: args.note || '',
    state: args.state || 'not_reviewed',
    companyName: args.company_name,
    companyWebsite: args.company_website,
    jobsUrl: args.jobs_url,
    companyDescription: args.company_description,
    addedAt: args.added_at,
  }));
}

function updateSite(args) {
  const updates = ['note', 'interval_days', 'next_review_days', 'state', 'company_name', 'company_website', 'jobs_url', 'company_description'];
  if (updates.every(key => args[key] == null)) throw new Error('at least one site field must be provided');

  const db = initDb(activeDbPath(args.db_path));
  const exists = db.prepare('SELECT 1 FROM sites WHERE id = ?').get(args.site_id);
  if (!exists) throw new Error(`site not found: ${args.site_id}`);

  if (args.note != null) {
    db.prepare("UPDATE sites SET note = ?, updated_at = strftime('%Y-%m-%dT%H:%M:%SZ','now') WHERE id = ?").run(args.note, args.site_id);
  }
  if (args.interval_days != null) setSiteNextReview(db, args.site_id, args.interval_days);
  if (args.next_review_days != null) setSiteNextReview(db, args.site_id, args.next_review_days);
  if (args.state != null) setSiteState(db, args.site_id, args.state);
  for (const [argName, column] of [
    ['company_name', 'company_name'],
    ['company_website', 'company_website'],
    ['jobs_url', 'jobs_url'],
    ['company_description', 'company_description'],
  ]) {
    if (args[argName] != null) {
      db.prepare(`UPDATE sites SET ${column} = ?, updated_at = strftime('%Y-%m-%dT%H:%M:%SZ','now') WHERE id = ?`).run(args[argName], args.site_id);
    }
  }
  return rowToObject(db.prepare('SELECT * FROM sites WHERE id = ?').get(args.site_id));
}

function workflowSnapshot(args) {
  const db = initDb(activeDbPath(args.db_path));
  const totalJobs = db.prepare('SELECT COUNT(*) AS n FROM jobs').get().n;
  const activeSites = db.prepare('SELECT COUNT(*) AS n FROM sites').get().n;
  const sitesDue = getSitesDueCount(db);
  const statusRows = db.prepare('SELECT status, COUNT(*) AS n FROM jobs GROUP BY status').all();
  const extractionRows = db.prepare('SELECT extraction_status, COUNT(*) AS n FROM jobs GROUP BY extraction_status').all();
  return {
    jobs_total: Number(totalJobs),
    sites_total: Number(activeSites),
    sites_due: Number(sitesDue),
    status_counts: Object.fromEntries(statusRows.map(row => [row.status, row.n])),
    extraction_status_counts: Object.fromEntries(extractionRows.map(row => [row.extraction_status, row.n])),
  };
}

const handlers = {
  jobs_list: jobsList,
  job_get: jobGet,
  add_capture: addCapture,
  update_job: updateJob,
  set_job_status: args => {
    updateJobStatus(args.job_id, args.status, activeDbPath(args.db_path));
    return { ok: true, job_id: args.job_id, status: args.status };
  },
  add_job_note: args => {
    addJobNote(args.job_id, args.note, activeDbPath(args.db_path));
    return { ok: true, job_id: args.job_id };
  },
  rerun_extraction: args => {
    resetJobExtraction(args.job_id, activeDbPath(args.db_path));
    return { ok: true, job_id: args.job_id, extraction_status: 'pending' };
  },
  list_sites: args => getSites(initDb(activeDbPath(args.db_path))).map(rowToObject),
  add_site: addSite,
  update_site: updateSite,
  delete_site: args => {
    const db = initDb(activeDbPath(args.db_path));
    const exists = db.prepare('SELECT 1 FROM sites WHERE id = ?').get(args.site_id);
    if (!exists) throw new Error(`site not found: ${args.site_id}`);
    deleteSite(db, args.site_id);
    return { ok: true, site_id: args.site_id };
  },
  workflow_snapshot: workflowSnapshot,
};

async function main() {
  parseArgs(process.argv.slice(2));
  const db = initDb(activeDbPath());
  getSettings(db);

  const server = new Server(
    { name: 'jobhunt', version: '0.1.0' },
    { capabilities: { tools: {} } },
  );

  server.setRequestHandler(ListToolsRequestSchema, async () => ({ tools }));
  server.setRequestHandler(CallToolRequestSchema, async request => {
    const name = request.params.name;
    const handler = handlers[name];
    if (!handler) throw new Error(`unknown tool: ${name}`);
    return textResult(handler(request.params.arguments || {}));
  });

  await server.connect(new StdioServerTransport());
}

main().catch(error => {
  console.error(error.stack || String(error));
  process.exit(1);
});
