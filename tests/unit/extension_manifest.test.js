import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { existsSync, readFileSync } from 'fs';
import { resolve } from 'path';

function readManifest() {
  return JSON.parse(readFileSync(resolve('extension/manifest.json'), 'utf8'));
}

function readServiceWorker() {
  return readFileSync(resolve('extension/service_worker.js'), 'utf8');
}

describe('extension manifest', () => {
  it('uses Manifest V3 with a service worker background', () => {
    const manifest = readManifest();

    assert.equal(manifest.manifest_version, 3);
    assert.equal(manifest.background.service_worker, 'service_worker.js');
    assert.equal(manifest.background.scripts, undefined);
    assert.equal(manifest.background.persistent, undefined);
  });

  it('declares the permissions used by the extension workflow', () => {
    const manifest = readManifest();

    for (const permission of ['activeTab', 'scripting', 'storage', 'contextMenus']) {
      assert.ok(manifest.permissions.includes(permission), `missing permission: ${permission}`);
    }
  });

  it('keeps localhost host permissions aligned with probed service-worker ports', () => {
    const manifest = readManifest();
    const source = readServiceWorker();
    const match = source.match(/const CANDIDATE_PORTS = \[([^\]]+)\]/);

    assert.ok(match, 'service worker must declare candidate ports');
    const ports = match[1].split(',').map((port) => parseInt(port.trim(), 10));

    for (const port of ports) {
      assert.ok(
        manifest.host_permissions.includes(`http://127.0.0.1:${port}/*`),
        `missing host permission for ${port}`
      );
    }
  });

  it('executeScript calls use world:MAIN so page JS vars (__next_f, __NEXT_DATA__) are accessible', () => {
    // Default world is ISOLATED, which cannot see page-level JS variables.
    // capture.js relies on win.__next_f and win.__NEXT_DATA__ for CSR pages like Cribl.
    // Without world:"MAIN" the extension captures only sparse DOM text and misses salary data.
    const source = readServiceWorker();

    // Find the captureTabPayload function body
    const fnStart = source.indexOf('async function captureTabPayload(');
    assert.ok(fnStart >= 0, 'captureTabPayload function must exist');
    // Take enough characters to cover the whole function (up to the next top-level function)
    const fnBody = source.slice(fnStart, fnStart + 3000);

    // Every executeScript block that loads capture.js or calls capturePage must specify world:MAIN
    const captureJsIdx = fnBody.indexOf('"capture.js"');
    const capturePageIdx = fnBody.indexOf('capturePage');
    assert.ok(captureJsIdx >= 0, 'captureTabPayload must inject capture.js');
    assert.ok(capturePageIdx >= 0, 'captureTabPayload must call capturePage');

    // Both blocks must have world:"MAIN" within 300 chars of the key identifier
    const captureJsBlock = fnBody.slice(Math.max(0, captureJsIdx - 150), captureJsIdx + 150);
    const capturePageBlock = fnBody.slice(Math.max(0, capturePageIdx - 150), capturePageIdx + 150);

    assert.ok(/world\s*:\s*["']MAIN["']/.test(captureJsBlock),
      'capture.js injection must use world:"MAIN" — without it, window.__next_f is invisible');
    assert.ok(/world\s*:\s*["']MAIN["']/.test(capturePageBlock),
      'capturePage call must use world:"MAIN" — without it, window.__next_f is invisible');
  });

  it('references packaged extension files that exist', () => {
    const manifest = readManifest();
    const files = [
      manifest.background.service_worker,
      ...Object.values(manifest.icons),
      ...Object.values(manifest.action.default_icon),
    ];

    for (const file of files) {
      assert.equal(existsSync(resolve('extension', file)), true, `missing extension file: ${file}`);
    }
  });
});
