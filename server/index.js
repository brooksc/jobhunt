#!/usr/bin/env node
// Entry point: CLI and server start. Mirrors python/src/jobhunt/cli.py

import { Command } from 'commander';
import * as db from './db.js';
import { jobsCsv } from './export.js';
import { makeExtractorFromSettings, makeScorerFromSettings, runExtraction } from './extract.js';

const program = new Command();
program.name('jobhunt').description('Local-first job tracking tool').version('0.1.0');

// ------------------------------------------------------------------
// serve
// ------------------------------------------------------------------

program.command('serve')
  .description('Start the local HTTP service')
  .option('--host <host>', 'Bind address', '127.0.0.1')
  .option('--port <port>', 'Port', '8765')
  .option('--db-path <path>', 'SQLite database path')
  .option('--auto-extract', 'Automatically run extraction after captures', true)
  .action(async (opts) => {
    const dbPath = opts.dbPath || process.env.JOBHUNT_DB_PATH;
    db.initDb(dbPath);
    db.requeueRunningRequests(dbPath, 0);

    const { createApp } = await import('./api.js');
    const app = createApp({ dbPath, autoExtract: opts.autoExtract });
    const port = parseInt(opts.port);
    app.listen(port, opts.host, () => {
      console.log(`jobhunt listening on http://${opts.host}:${port}`);
      console.log(`Database: ${dbPath || db.defaultDbPath()}`);
    });
  });

// ------------------------------------------------------------------
// init
// ------------------------------------------------------------------

program.command('init')
  .description('Initialize the database')
  .option('--db-path <path>', 'SQLite database path')
  .action((opts) => {
    const dbPath = opts.dbPath || process.env.JOBHUNT_DB_PATH;
    db.initDb(dbPath);
    console.log(`Database initialized: ${dbPath || db.defaultDbPath()}`);
  });

// ------------------------------------------------------------------
// extract
// ------------------------------------------------------------------

program.command('extract')
  .description('Run LLM extraction on pending captures')
  .option('--db-path <path>', 'SQLite database path')
  .option('--llm-base-url <url>', 'LM Studio base URL')
  .option('--model <model>', 'LLM model name')
  .option('--timeout <seconds>', 'Request timeout', '300')
  .option('--limit <n>', 'Max extractions to run', '10')
  .action(async (opts) => {
    const dbPath = opts.dbPath || process.env.JOBHUNT_DB_PATH;
    const d = db.initDb(dbPath);
    const settings = db.getSettings(d);
    if (opts.llmBaseUrl) settings.llm_base_url = opts.llmBaseUrl;
    if (opts.model) settings.llm_model = opts.model;
    if (opts.timeout) settings.llm_timeout = opts.timeout;

    const extractor = makeExtractorFromSettings(settings);
    const scorer = makeScorerFromSettings(settings);
    const limit = parseInt(opts.limit || '10');

    console.log(`Extracting up to ${limit} jobs...`);
    const summary = await runExtraction({ dbPath, extractor, limit, scorer });
    console.log(`Done: ${summary.processed} processed, ${summary.succeeded} succeeded, ${summary.failed} failed`);
  });

// ------------------------------------------------------------------
// jobs
// ------------------------------------------------------------------

const jobsCmd = program.command('jobs').description('Manage jobs');

jobsCmd.command('list')
  .description('List jobs')
  .option('--db-path <path>', 'SQLite database path')
  .option('--status <status>', 'Filter by status')
  .option('--limit <n>', 'Max results', '100')
  .action((opts) => {
    const dbPath = opts.dbPath || process.env.JOBHUNT_DB_PATH;
    const d = db.initDb(dbPath);
    let rows = d.prepare(`SELECT jobs.job_number, jobs.company, jobs.title, jobs.status,
      COALESCE(captures.canonical_url, captures.url) AS source_url
      FROM jobs JOIN captures ON captures.id=jobs.capture_id
      ORDER BY captures.captured_at DESC LIMIT ?`).all(parseInt(opts.limit));
    if (opts.status) rows = rows.filter(r => r.status === opts.status);
    for (const row of rows) {
      console.log(`#${row.job_number} [${row.status}] ${row.company || '?'} — ${row.title || '?'} (${row.source_url})`);
    }
  });

jobsCmd.command('status <jobId> <status>')
  .description('Update job status')
  .option('--db-path <path>', 'SQLite database path')
  .action((jobId, status, opts) => {
    const dbPath = opts.dbPath || process.env.JOBHUNT_DB_PATH;
    db.updateJobStatus(jobId, status, dbPath);
    console.log(`Updated job ${jobId} → ${status}`);
  });

jobsCmd.command('note <jobId> <note>')
  .description('Add a note to a job')
  .option('--db-path <path>', 'SQLite database path')
  .action((jobId, note, opts) => {
    const dbPath = opts.dbPath || process.env.JOBHUNT_DB_PATH;
    db.addJobNote(jobId, note, dbPath);
    console.log(`Note added to ${jobId}`);
  });

jobsCmd.command('queue-ai <jobNumbers>')
  .description('Queue AI processing for visible job numbers, e.g. "19,74,#90"')
  .option('--db-path <path>', 'SQLite database path')
  .option('--mode <mode>', 'extract, fit_score, or missing_fields', 'extract')
  .option('--process', 'Start processing the queue immediately', false)
  .option('--limit <n>', 'Max queued requests to process when --process is used', '100')
  .action(async (jobNumbers, opts) => {
    const dbPath = opts.dbPath || process.env.JOBHUNT_DB_PATH;
    const numbers = String(jobNumbers).split(',').map(n => n.trim()).filter(Boolean);
    db.initDb(dbPath);
    const result = db.queueBulkLlmJobsByNumbers(numbers, opts.mode, dbPath);
    console.log(`Queued ${result.queued}/${result.found} found jobs (${result.requested} requested)`);
    if (result.missing_job_numbers.length) {
      console.log(`Missing job numbers: ${result.missing_job_numbers.map(n => `#${n}`).join(', ')}`);
    }
    if (opts.process) {
      const d = db.initDb(dbPath);
      const settings = db.getSettings(d);
      const extractor = makeExtractorFromSettings(settings);
      const scorer = makeScorerFromSettings(settings);
      const limit = parseInt(opts.limit || '100');
      const summary = await runExtraction({ dbPath, extractor, limit, scorer });
      console.log(`Processed: ${summary.processed} processed, ${summary.succeeded} succeeded, ${summary.failed} failed`);
    }
  });

// ------------------------------------------------------------------
// duplicates
// ------------------------------------------------------------------

const duplicatesCmd = program.command('duplicates').description('Manage duplicates');

duplicatesCmd.command('list')
  .description('List duplicate candidate groups')
  .option('--db-path <path>', 'SQLite database path')
  .option('--limit <n>', 'Max results', '50')
  .action((opts) => {
    const dbPath = opts.dbPath || process.env.JOBHUNT_DB_PATH;
    const d = db.initDb(dbPath);
    const rows = d.prepare(`SELECT captures.cleaned_hash, jobs.id AS job_id, jobs.company,
      COALESCE(jobs.title, captures.page_title) AS title,
      COALESCE(captures.canonical_url, captures.url) AS source_url
      FROM captures JOIN jobs ON jobs.capture_id=captures.id
      WHERE captures.cleaned_hash IN (
        SELECT cleaned_hash FROM captures WHERE cleaned_hash IS NOT NULL
        GROUP BY cleaned_hash HAVING COUNT(DISTINCT COALESCE(canonical_url, url)) > 1
      ) ORDER BY captures.cleaned_hash LIMIT ?`).all(parseInt(opts.limit));
    const grouped = {};
    for (const row of rows) {
      if (!grouped[row.cleaned_hash]) grouped[row.cleaned_hash] = [];
      grouped[row.cleaned_hash].push(row);
    }
    for (const [hash, group] of Object.entries(grouped)) {
      console.log(`Group ${hash.slice(0, 8)}...:`);
      for (const row of group) {
        console.log(`  ${row.company || '?'} — ${row.title || '?'} (${row.source_url})`);
      }
    }
  });

// ------------------------------------------------------------------
// export
// ------------------------------------------------------------------

const exportCmd = program.command('export').description('Export data');

exportCmd.command('csv')
  .description('Export jobs to CSV')
  .option('--db-path <path>', 'SQLite database path')
  .option('--output <file>', 'Output file (default: stdout)')
  .action(async (opts) => {
    const dbPath = opts.dbPath || process.env.JOBHUNT_DB_PATH;
    const csv = jobsCsv(dbPath);
    if (opts.output) {
      const { writeFileSync, mkdirSync } = await import('fs');
      const { dirname } = await import('path');
      mkdirSync(dirname(opts.output), { recursive: true });
      writeFileSync(opts.output, csv);
      console.log(`Exported to ${opts.output}`);
    } else {
      process.stdout.write(csv);
    }
  });

program.parse(process.argv);
