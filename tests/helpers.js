import { randomBytes } from 'crypto';
import { tmpdir } from 'os';
import { join } from 'path';
import { rmSync, existsSync } from 'fs';

export function tempDbPath() {
  return join(tmpdir(), `jobhunt-test-${randomBytes(8).toString('hex')}.db`);
}

export function cleanupDb(dbPath) {
  for (const ext of ['', '-wal', '-shm']) {
    try { rmSync(dbPath + ext); } catch { /* ignore */ }
  }
}

export const CAPTURE = {
  url: 'https://example.com/jobs/123',
  page_title: 'Software Engineer at Acme',
  visible_text: 'We are looking for a software engineer with 5+ years of experience in distributed systems.',
};

export const CAPTURE2 = {
  url: 'https://other.com/jobs/456',
  page_title: 'Staff Engineer at Globex',
  visible_text: 'Seeking a staff engineer to lead platform teams.',
};
