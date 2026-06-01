import { readFileSync } from 'fs';
import { describe, it } from 'node:test';
import assert from 'node:assert/strict';

describe('Electron shell smoke', () => {
  it('starts the server with an app userData database and preferred extension ports', () => {
    const source = readFileSync('electron/main.js', 'utf8');

    assert.match(source, /app\.getPath\('userData'\)/);
    assert.match(source, /process\.env\.JOBHUNT_DB_PATH\s*=\s*dbPath/);
    assert.match(source, /createApp\(\{\s*dbPath,\s*autoExtract:\s*true\s*\}\)/);
    assert.match(source, /PREFERRED_PORTS\s*=\s*\[8765,\s*8766,\s*8767,\s*8768,\s*8769\]/);
    assert.match(source, /setWindowOpenHandler/);
  });
});
