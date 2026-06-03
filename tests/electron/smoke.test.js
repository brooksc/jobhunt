import { readFileSync } from 'fs';
import { describe, it } from 'node:test';
import assert from 'node:assert/strict';

describe('Electron shell smoke', () => {
  it('starts the server with the shared config database and preferred extension ports', () => {
    const source = readFileSync('electron/main.js', 'utf8');

    assert.match(source, /path\.join\(os\.homedir\(\),\s*'\.config',\s*'jobhunt',\s*'jobhunt\.db'\)/);
    assert.match(source, /process\.env\.JOBHUNT_DB_PATH\s*=\s*dbPath/);
    assert.match(source, /createApp\(\{[^}]*dbPath[^}]*autoExtract:\s*true[^}]*\}\)/);
    assert.match(source, /minWidth:\s*960/);
    assert.match(source, /minHeight:\s*600/);
    assert.match(source, /PREFERRED_PORTS\s*=\s*\[8765,\s*8766,\s*8767,\s*8768,\s*8769\]/);
    assert.match(source, /No preferred extension port available/);
    assert.doesNotMatch(source, /tryPort\(0\)/);
    assert.match(source, /setWindowOpenHandler/);
  });

  it('declares host permissions for every preferred extension port', () => {
    const manifest = JSON.parse(readFileSync('extension/manifest.json', 'utf8'));

    for (const port of [8765, 8766, 8767, 8768, 8769]) {
      assert.ok(
        manifest.host_permissions.includes(`http://127.0.0.1:${port}/*`),
        `missing host permission for ${port}`
      );
    }
  });
});
