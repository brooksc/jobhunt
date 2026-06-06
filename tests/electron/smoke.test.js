import { readFileSync } from 'fs';
import { describe, it } from 'node:test';
import assert from 'node:assert/strict';

const mainSource = readFileSync('electron/main.js', 'utf8');

describe('Electron shell smoke', () => {
  it('starts the server with the shared config database and preferred extension ports', () => {
    assert.match(mainSource, /app\.getPath\('userData'\)/);
    assert.match(mainSource, /process\.env\.JOBHUNT_DB_PATH\s*=\s*dbPath/);
    assert.match(mainSource, /createApp\(\{[^}]*dbPath[^}]*autoExtract:\s*true[^}]*\}\)/);
    assert.match(mainSource, /minWidth:\s*960/);
    assert.match(mainSource, /minHeight:\s*600/);
    assert.match(mainSource, /PREFERRED_PORTS\s*=\s*\[8765,\s*8766,\s*8767,\s*8768,\s*8769\]/);
    assert.match(mainSource, /No preferred extension port available/);
    assert.doesNotMatch(mainSource, /tryPort\(0\)/);
    assert.match(mainSource, /setWindowOpenHandler/);
  });

  it('guards auto-update behind !process.mas and app.isPackaged with error handling', () => {
    assert.match(mainSource, /if\s*\(\s*!process\.mas\s*&&\s*app\.isPackaged\s*\)/);
    assert.match(mainSource, /checkForUpdatesAndNotify\(\)\s*\.catch\(/);
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
