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
