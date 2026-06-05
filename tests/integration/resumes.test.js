import { describe, it, before, after } from 'node:test';
import assert from 'node:assert/strict';
import { DatabaseSync } from 'node:sqlite';
import { mkdtempSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import {
  initDb, insertCapture, markExtractionSucceeded,
  addResume, listResumes, getActiveResumes, getResume,
  renameResume, updateResumeText, setResumeActive, deleteResume,
  queueFitScoresForAllResumes,
  markFitSucceeded, markFitFailed, getLlmRequestsByIds,
} from '../../server/db.js';
import { tempDbPath, cleanupDb, CAPTURE } from '../helpers.js';

const EXTRACTED = {
  company: 'X', title: 'Engineer', location: 'Remote', remote_type: 'remote',
  salary_min: null, salary_max: null, salary_currency: null, salary_note: null,
  employment_type: 'full_time', seniority: 'senior', skills: ['js'],
  summary: 'role', requirements: ['js'], nice_to_haves: [], benefits: [],
  application_url: null, confidence: {},
};

function makeScoredJob(dbPath) {
  const { job_id } = insertCapture(CAPTURE, dbPath);
  markExtractionSucceeded(job_id, EXTRACTED, dbPath, null, 'm', 0.9);
  return job_id;
}

describe('resume CRUD', () => {
  let dbPath;
  before(() => { dbPath = tempDbPath(); initDb(dbPath); });
  after(() => cleanupDb(dbPath));

  it('adds, lists, renames, edits text, toggles active, and deletes', () => {
    const r = addResume(dbPath, { name: 'Alpha', filename: 'a.pdf', text: 'hello world' });
    assert.equal(r.name, 'Alpha');
    assert.equal(r.char_count, 'hello world'.length);
    assert.equal(r.active, 1);

    assert.equal(listResumes(dbPath).length, 1);
    assert.equal(listResumes(dbPath)[0].text, undefined); // list omits text payload
    assert.equal(getResume(dbPath, r.id).text, 'hello world');

    renameResume(dbPath, r.id, 'Beta');
    assert.equal(getResume(dbPath, r.id).name, 'Beta');

    updateResumeText(dbPath, r.id, 'new longer text body');
    assert.equal(getResume(dbPath, r.id).char_count, 'new longer text body'.length);

    setResumeActive(dbPath, r.id, false);
    assert.equal(getActiveResumes(dbPath).length, 0);
    setResumeActive(dbPath, r.id, true);
    assert.equal(getActiveResumes(dbPath).length, 1);

    deleteResume(dbPath, r.id);
    assert.equal(listResumes(dbPath).length, 0);
  });

  it('getActiveResumes only returns active resumes, ordered', () => {
    const a = addResume(dbPath, { name: 'One', text: 'one' });
    const b = addResume(dbPath, { name: 'Two', text: 'two' });
    setResumeActive(dbPath, b.id, false);
    const active = getActiveResumes(dbPath);
    assert.equal(active.length, 1);
    assert.equal(active[0].id, a.id);
  });
});

describe('per-resume fit rollup', () => {
  let dbPath, jobId, r1, r2;
  before(() => {
    dbPath = tempDbPath();
    initDb(dbPath);
    jobId = makeScoredJob(dbPath);
    r1 = addResume(dbPath, { name: 'Lower', text: 'resume one' });
    r2 = addResume(dbPath, { name: 'Higher', text: 'resume two' });
  });
  after(() => cleanupDb(dbPath));

  it('queues one fit request per active resume', () => {
    const ids = queueFitScoresForAllResumes(dbPath, jobId, { resetAttempts: true });
    assert.equal(ids.length, 2);
    const items = getLlmRequestsByIds(ids, dbPath);
    assert.ok(items.every(i => i.request_type === 'fit_score' && i.resume_id));
    const db = initDb(dbPath);
    assert.equal(db.prepare("SELECT fit_status FROM jobs WHERE id=?").get(jobId).fit_status, 'pending');
  });

  it('rolls jobs.fit_score up to the best resume score with best markers', () => {
    markFitSucceeded(jobId, r1.id, { overall_score: 60, summary: 's1', dimensions: [] }, dbPath, null, 'm');
    markFitSucceeded(jobId, r2.id, { overall_score: 85, summary: 's2', dimensions: [] }, dbPath, null, 'm');
    const db = initDb(dbPath);
    const job = db.prepare("SELECT fit_score, fit_status, fit_score_json FROM jobs WHERE id=?").get(jobId);
    assert.equal(job.fit_score, 85);
    assert.equal(job.fit_status, 'succeeded');
    const payload = JSON.parse(job.fit_score_json);
    assert.equal(payload.best_resume_id, r2.id);
    assert.equal(payload.best_resume_name, 'Higher');
  });

  it('recomputes to the next-best score when the best resume is deleted', () => {
    deleteResume(dbPath, r2.id);
    const db = initDb(dbPath);
    const job = db.prepare("SELECT fit_score, fit_status FROM jobs WHERE id=?").get(jobId);
    assert.equal(job.fit_score, 60);
    assert.equal(job.fit_status, 'succeeded');
    // The deleted resume's per-resume row is gone (FK cascade).
    assert.equal(db.prepare("SELECT COUNT(*) AS c FROM job_fit_scores WHERE job_id=?").get(jobId).c, 1);
  });

  it('markFitFailed rolls up to failed only when no resume succeeded', () => {
    const localPath = tempDbPath();
    initDb(localPath);
    const j = makeScoredJob(localPath);
    const a = addResume(localPath, { name: 'A', text: 'a' });
    markFitFailed(j, a.id, 'boom', localPath, null);
    const db = initDb(localPath);
    const job = db.prepare("SELECT fit_status, fit_score FROM jobs WHERE id=?").get(j);
    assert.equal(job.fit_status, 'failed');
    assert.equal(job.fit_score, null);
    cleanupDb(localPath);
  });
});

describe('legacy resume_text migration', () => {
  let dir, dbPath;
  before(() => {
    dir = mkdtempSync(join(tmpdir(), 'jhmig-'));
    dbPath = join(dir, 'old.db');
    const raw = new DatabaseSync(dbPath);
    raw.exec('PRAGMA foreign_keys=ON');
    raw.exec(`CREATE TABLE captures (id TEXT PRIMARY KEY, url TEXT NOT NULL, canonical_url TEXT, page_title TEXT NOT NULL, selected_text TEXT, visible_text TEXT, cleaned_description TEXT, structured_data_json TEXT, user_note TEXT, raw_hash TEXT NOT NULL, cleaned_hash TEXT, captured_at TEXT NOT NULL, created_at TEXT NOT NULL, UNIQUE(raw_hash))`);
    raw.exec(`CREATE TABLE jobs (id TEXT PRIMARY KEY, job_number INTEGER UNIQUE, capture_id TEXT NOT NULL REFERENCES captures(id), company TEXT, title TEXT, status TEXT NOT NULL DEFAULT 'saved', extraction_status TEXT NOT NULL DEFAULT 'pending', extracted_json TEXT, fit_score INTEGER, fit_status TEXT NOT NULL DEFAULT 'none', fit_score_json TEXT, created_at TEXT NOT NULL, updated_at TEXT NOT NULL)`);
    raw.exec(`CREATE TABLE settings (key TEXT PRIMARY KEY, value TEXT NOT NULL, updated_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%SZ','now')))`);
    raw.exec(`CREATE TABLE llm_requests (id TEXT PRIMARY KEY, job_id TEXT NOT NULL REFERENCES jobs(id) ON DELETE CASCADE, request_type TEXT NOT NULL DEFAULT 'extract', status TEXT NOT NULL DEFAULT 'queued', attempt INTEGER NOT NULL DEFAULT 1, model TEXT, error TEXT, created_at TEXT NOT NULL, started_at TEXT, finished_at TEXT, UNIQUE(job_id, request_type))`);
    raw.exec(`CREATE TABLE llm_request_attempts (id TEXT PRIMARY KEY, request_id TEXT NOT NULL REFERENCES llm_requests(id) ON DELETE CASCADE, job_id TEXT NOT NULL REFERENCES jobs(id) ON DELETE CASCADE, request_type TEXT NOT NULL, attempt INTEGER NOT NULL, status TEXT NOT NULL, started_at TEXT NOT NULL)`);
    const now = '2026-01-01T00:00:00Z';
    raw.prepare("INSERT INTO captures (id,url,page_title,raw_hash,captured_at,created_at) VALUES ('cap1','u','t','h1',?,?)").run(now, now);
    raw.prepare("INSERT INTO jobs (id,job_number,capture_id,company,title,status,extraction_status,extracted_json,fit_score,fit_status,fit_score_json,created_at,updated_at) VALUES ('job1',1,'cap1','X','Eng','saved','succeeded',?,77,'succeeded',?,?,?)")
      .run(JSON.stringify({ title: 'Eng' }), JSON.stringify({ overall_score: 77, summary: 'ok', model: 'gemma', scored_at: now, dimensions: [] }), now, now);
    raw.prepare("INSERT INTO settings (key,value) VALUES ('resume_text','my old resume text')").run();
    raw.prepare("INSERT INTO llm_requests (id,job_id,request_type,status,attempt,created_at) VALUES ('lr1','job1','extract','succeeded',1,?)").run(now);
    raw.prepare("INSERT INTO llm_requests (id,job_id,request_type,status,attempt,created_at) VALUES ('lr2','job1','fit_score','queued',1,?)").run(now);
    raw.close();
  });
  after(() => cleanupDb(dbPath));

  it('migrates resume_text into a resume and copies existing fit scores', () => {
    const d = initDb(dbPath);
    const cols = d.prepare("PRAGMA table_info(llm_requests)").all().map(c => c.name);
    assert.ok(cols.includes('resume_id'));

    const resumes = listResumes(dbPath);
    assert.equal(resumes.length, 1);
    assert.equal(resumes[0].name, 'Imported resume');

    const jfs = d.prepare("SELECT job_id, fit_score, fit_status FROM job_fit_scores").all();
    assert.equal(jfs.length, 1);
    assert.equal(jfs[0].fit_score, 77);

    // Legacy extract request preserved, legacy fit request dropped, setting removed.
    assert.ok(d.prepare("SELECT id FROM llm_requests WHERE id='lr1'").get());
    assert.equal(d.prepare("SELECT id FROM llm_requests WHERE id='lr2'").get(), undefined);
    assert.equal(d.prepare("SELECT value FROM settings WHERE key='resume_text'").get(), undefined);
  });

  it('is idempotent across repeated init', () => {
    initDb(dbPath);
    assert.equal(listResumes(dbPath).length, 1);
  });
});
