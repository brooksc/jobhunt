// Bridge to Apple's FoundationModels framework via a persistent Swift subprocess.
// Spawns native/foundation-models/foundation-models once; routes all requests
// through its stdin/stdout so there's no per-request startup overhead.

import { spawn } from 'node:child_process';
import { createInterface } from 'node:readline';
import { existsSync } from 'node:fs';
import { release as osRelease } from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { randomUUID } from 'node:crypto';

const __dirname = path.dirname(fileURLToPath(import.meta.url));

// Location of the compiled Swift binary — next to the server in dev, or in
// Electron's extraResources in a packaged build.
function binaryPath() {
  const devPath = path.join(__dirname, '../native/foundation-models/foundation-models');
  if (existsSync(devPath)) return devPath;
  // Electron packaged: process.resourcesPath is set by Electron
  if (process.resourcesPath) {
    const pkgPath = path.join(process.resourcesPath, 'foundation-models');
    if (existsSync(pkgPath)) return pkgPath;
  }
  return null;
}

// Returns true if this runtime can use Foundation Models (macOS 26+).
export function isAvailable() {
  if (process.platform !== 'darwin') return false;
  return _releaseSupported(osRelease());
}

// Exported for testing — checks Darwin release string against the macOS 26 minimum.
export function _releaseSupported(releaseStr) {
  const rel = Number(releaseStr.split('.')[0]);
  return rel >= 25; // Darwin 25.x = macOS 26.x
}

let _proc = null;
let _ready = false;
const _pending = new Map(); // id → { resolve, reject }

function getProcess() {
  if (_proc && !_proc.killed) return _proc;

  const bin = binaryPath();
  if (!bin) throw new Error('Apple Foundation Models binary not found. Run: npm run build:native');

  _proc = spawn(bin, [], { stdio: ['pipe', 'pipe', 'pipe'] });
  _ready = false;

  const rl = createInterface({ input: _proc.stdout });
  rl.on('line', (line) => {
    let msg;
    try { msg = JSON.parse(line); } catch { return; }

    if (msg.ready) { _ready = true; return; }

    const prom = _pending.get(msg.id);
    if (!prom) return;
    _pending.delete(msg.id);

    if (msg.error) prom.reject(new Error(msg.error));
    else prom.resolve(msg.content ?? '');
  });

  _proc.stderr.on('data', (d) => {
    process.stderr.write(`[foundation-models] ${d}`);
  });

  _proc.on('exit', (code) => {
    _proc = null;
    _ready = false;
    // Reject any in-flight requests
    for (const [id, prom] of _pending) {
      _pending.delete(id);
      prom.reject(new Error(`Foundation Models process exited (code ${code})`));
    }
  });

  return _proc;
}

function waitReady(proc, timeoutMs = 10000) {
  if (_ready) return Promise.resolve();
  return new Promise((resolve, reject) => {
    const deadline = setTimeout(() => reject(new Error('Foundation Models process did not become ready')), timeoutMs);
    const check = setInterval(() => {
      if (_ready || proc.killed) {
        clearInterval(check);
        clearTimeout(deadline);
        if (_ready) resolve();
        else reject(new Error('Foundation Models process died during startup'));
      }
    }, 50);
  });
}

export async function complete({ system, prompt, timeout = 120 }) {
  const proc = getProcess();
  await waitReady(proc);

  const id = randomUUID();
  const req = JSON.stringify({ id, system: system ?? null, prompt });

  return new Promise((resolve, reject) => {
    const timer = setTimeout(() => {
      _pending.delete(id);
      reject(new Error(`Foundation Models request timed out after ${timeout}s`));
    }, timeout * 1000);

    _pending.set(id, {
      resolve: (v) => { clearTimeout(timer); resolve(v); },
      reject:  (e) => { clearTimeout(timer); reject(e); },
    });

    proc.stdin.write(req + '\n');
  });
}

// Graceful shutdown — called when the server exits.
export function shutdown() {
  if (_proc && !_proc.killed) _proc.kill();
}
