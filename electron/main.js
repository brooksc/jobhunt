// Electron main process: starts the Express server then opens a BrowserWindow.
import { app, BrowserWindow, shell, globalShortcut } from 'electron';
import path from 'path';
import { fileURLToPath } from 'url';

const __dirname = path.dirname(fileURLToPath(import.meta.url));

let mainWindow = null;
let serverPort = null;

async function startServer() {
  const dbPath = path.join(app.getPath('userData'), 'jobhunt.db');
  process.env.JOBHUNT_DB_PATH = dbPath;

  const { initDb, requeueRunningRequests } = await import('../server/db.js');
  initDb(dbPath);
  requeueRunningRequests(dbPath, 0);

  const { createApp } = await import('../server/api.js');
  const expressApp = createApp({ dbPath, autoExtract: true });

  // Try preferred ports in order so the extension can find us predictably.
  // Fall back to an OS-assigned port if all are busy.
  const PREFERRED_PORTS = [8765, 8766, 8767, 8768, 8769];

  const tryPort = (port) => new Promise((resolve, reject) => {
    const server = expressApp.listen(port, '127.0.0.1', () => resolve(server));
    server.on('error', reject);
  });

  for (const port of PREFERRED_PORTS) {
    try {
      const server = await tryPort(port);
      return server.address().port;
    } catch (err) {
      if (err.code !== 'EADDRINUSE') throw err;
    }
  }
  // All preferred ports busy — let the OS pick
  const server = await tryPort(0);
  return server.address().port;
}

async function createWindow() {
  mainWindow = new BrowserWindow({
    width: 1280,
    height: 860,
    titleBarStyle: 'hiddenInset',
    webPreferences: {
      nodeIntegration: false,
      contextIsolation: true,
    },
  });

  // Open external links in the system browser, not inside the app
  mainWindow.webContents.setWindowOpenHandler(({ url }) => {
    if (!url.startsWith('http://127.0.0.1')) shell.openExternal(url);
    return { action: 'deny' };
  });

  await mainWindow.loadURL(`http://127.0.0.1:${serverPort}`);

  // Push sidebar content down/right so macOS traffic lights don't overlap.
  // hiddenInset places buttons at ~(10,10); brand row is the first thing in the sidebar.
  mainWindow.webContents.insertCSS(`
    .jh-side { padding-top: 36px; -webkit-app-region: drag; }
    .jh-side > * { -webkit-app-region: no-drag; }
    .jh-main { -webkit-app-region: no-drag; }
  `);

  mainWindow.on('closed', () => { mainWindow = null; });
}

app.whenReady().then(async () => {
  try {
    serverPort = await startServer();
    await createWindow();
  } catch (err) {
    console.error('Failed to start:', err);
    app.quit();
  }

  // Cmd+Option+I → toggle DevTools
  globalShortcut.register('CommandOrControl+Alt+I', () => {
    if (mainWindow) mainWindow.webContents.toggleDevTools();
  });

  // macOS: re-open window when clicking dock icon with no windows open
  app.on('activate', () => {
    if (!mainWindow && serverPort) createWindow();
  });
});

app.on('window-all-closed', () => {
  if (process.platform !== 'darwin') app.quit();
});
